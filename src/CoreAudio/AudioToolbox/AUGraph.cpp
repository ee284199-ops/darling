/*
This file is part of Darling.

Copyright (C) 2026 Darling Developers

Darling is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Darling is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "AUGraph.h"

#include <CarbonCore/Components.h>
#include <CarbonCore/MacErrors.h>

#include <cstddef>
#include <map>
#include <mutex>
#include <utility>
#include <vector>

// ____________________________________________________________________________
//
// An AUGraph is a set of nodes, each wrapping an AudioUnit, plus the
// connections between those nodes. The graph itself never processes audio:
// when it is started the output node(s) pull audio from their inputs.
//
// A connection is realised in one of two ways:
//   * preferred: kAudioUnitProperty_MakeConnection on the destination input,
//     which lets the audio unit pull the source directly (the destination's
//     AUBase copies the source output stream format for us);
//   * fallback: a render callback installed on the destination input, whose
//     refCon points at a ConnectionRenderContext kept alive by the graph. The
//     callback pulls the source unit with AudioUnitRender().
//
// The graph mutex only guards graph mutation. Render callbacks never take it.
// ____________________________________________________________________________

namespace
{

// Per-connection data referenced from a fallback render callback. Allocated
// per connection and owned by the graph until it is disposed.
struct ConnectionRenderContext
{
	AudioUnit sourceUnit;
	UInt32 sourceOutputNumber;
	UInt32 destInputNumber;
};

} // namespace

// The render callback used for connections the destination cannot express with
// kAudioUnitProperty_MakeConnection. It simply pulls the source unit.
extern "C" OSStatus AUGraphConnectionRenderCallback(void* inRefCon,
	AudioUnitRenderActionFlags* ioActionFlags,
	const AudioTimeStamp* inTimeStamp,
	UInt32 inBusNumber,
	UInt32 inNumberFrames,
	AudioBufferList* ioData)
{
	(void) inBusNumber;

	ConnectionRenderContext* context = static_cast<ConnectionRenderContext*>(inRefCon);

	if (context == nullptr || context->sourceUnit == nullptr)
		return kAudioUnitErr_NoConnection;

	return AudioUnitRender(context->sourceUnit, ioActionFlags, inTimeStamp,
		context->sourceOutputNumber, inNumberFrames, ioData);
}

struct AUGraphData
{
	struct Node
	{
		AUNode id;
		AudioComponentDescription desc;
		AudioUnit unit;
		std::map<UInt32, AURenderCallbackStruct> inputCallbacks;
	};

	struct Connection
	{
		AUNode sourceNode;
		UInt32 sourceOutputNumber;
		AUNode destNode;
		UInt32 destInputNumber;
		bool applied;
		bool viaCallback;
		ConnectionRenderContext* context;
	};

	std::mutex mutex;
	std::vector<Node> nodes;
	std::vector<Connection> connections;
	std::vector<std::pair<AURenderCallback, void*> > renderNotifies;
	std::vector<ConnectionRenderContext*> contexts;
	AUNode nextNodeId = 1;
	bool open = false;
	bool initialized = false;
	bool running = false;
};

// ____________________________________________________________________________
// Helpers. These assume the graph mutex is already held.

static AUGraphData::Node* AUGraphFindNode(AUGraphData* graph, AUNode node)
{
	for (AUGraphData::Node& n : graph->nodes)
	{
		if (n.id == node)
			return &n;
	}
	return nullptr;
}

static size_t AUGraphIndexOfNode(AUGraphData* graph, AUNode node)
{
	for (size_t i = 0; i < graph->nodes.size(); i++)
	{
		if (graph->nodes[i].id == node)
			return i;
	}
	return graph->nodes.size();
}

static size_t AUGraphIndexOfConnection(AUGraphData* graph, AUNode destNode, UInt32 destInputNumber)
{
	for (size_t i = 0; i < graph->connections.size(); i++)
	{
		if (graph->connections[i].destNode == destNode &&
			graph->connections[i].destInputNumber == destInputNumber)
			return i;
	}
	return graph->connections.size();
}

static OSStatus AUGraphInstantiateNode(AUGraphData* graph, AUGraphData::Node& node)
{
	if (node.unit != nullptr)
		return noErr;

	AudioComponent component = AudioComponentFindNext(nullptr, &node.desc);
	if (component == nullptr)
		return kAUGraphErr_InvalidAudioUnit;

	OSStatus status = AudioComponentInstanceNew(component, &node.unit);
	if (status != noErr)
	{
		node.unit = nullptr;
		return status;
	}

	for (auto& entry : node.inputCallbacks)
	{
		AudioUnitSetProperty(node.unit, kAudioUnitProperty_SetRenderCallback,
			kAudioUnitScope_Input, entry.first, &entry.second, sizeof(entry.second));
	}

	if (node.desc.componentType == kAudioUnitType_Output)
	{
		for (auto& notify : graph->renderNotifies)
			AudioUnitAddRenderNotify(node.unit, notify.first, notify.second);
	}

	return noErr;
}

static void AUGraphDestroyNodeUnit(AUGraphData::Node& node)
{
	if (node.unit != nullptr)
	{
		AudioComponentInstanceDispose(node.unit);
		node.unit = nullptr;
	}
}

static OSStatus AUGraphApplyConnection(AUGraphData* graph, AUGraphData::Connection& connection)
{
	AUGraphData::Node* source = AUGraphFindNode(graph, connection.sourceNode);
	AUGraphData::Node* dest = AUGraphFindNode(graph, connection.destNode);

	if (source == nullptr || dest == nullptr)
		return kAUGraphErr_NodeNotFound;
	if (source->unit == nullptr || dest->unit == nullptr)
		return kAUGraphErr_CannotDoInCurrentContext;

	// Bring the destination input in line with the source output where the
	// destination allows it. Failures are deliberately ignored.
	AudioStreamBasicDescription sourceFormat;
	UInt32 formatSize = sizeof(sourceFormat);
	if (AudioUnitGetProperty(source->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output,
			connection.sourceOutputNumber, &sourceFormat, &formatSize) == noErr)
	{
		AudioUnitSetProperty(dest->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input,
			connection.destInputNumber, &sourceFormat, sizeof(sourceFormat));
	}

	AudioUnitConnection auConnection;
	auConnection.sourceAudioUnit = source->unit;
	auConnection.sourceOutputNumber = connection.sourceOutputNumber;
	auConnection.destInputNumber = connection.destInputNumber;

	OSStatus status = AudioUnitSetProperty(dest->unit, kAudioUnitProperty_MakeConnection,
		kAudioUnitScope_Input, connection.destInputNumber, &auConnection, sizeof(auConnection));

	if (status != noErr)
	{
		// The destination does not do AU connections; pull it by hand instead.
		ConnectionRenderContext* context = new ConnectionRenderContext();
		context->sourceUnit = source->unit;
		context->sourceOutputNumber = connection.sourceOutputNumber;
		context->destInputNumber = connection.destInputNumber;
		graph->contexts.push_back(context);

		AURenderCallbackStruct callback;
		callback.inputProc = AUGraphConnectionRenderCallback;
		callback.inputProcRefCon = context;

		status = AudioUnitSetProperty(dest->unit, kAudioUnitProperty_SetRenderCallback,
			kAudioUnitScope_Input, connection.destInputNumber, &callback, sizeof(callback));
		if (status != noErr)
			return status;

		connection.viaCallback = true;
		connection.context = context;
	}

	connection.applied = true;
	return noErr;
}

static OSStatus AUGraphApplyPendingConnections(AUGraphData* graph)
{
	for (AUGraphData::Connection& connection : graph->connections)
	{
		if (connection.applied)
			continue;

		OSStatus status = AUGraphApplyConnection(graph, connection);
		if (status != noErr)
			return status;
	}
	return noErr;
}

static void AUGraphRemoveConnection(AUGraphData* graph, size_t index)
{
	AUGraphData::Connection& connection = graph->connections[index];

	if (connection.applied)
	{
		AUGraphData::Node* dest = AUGraphFindNode(graph, connection.destNode);

		if (dest != nullptr && dest->unit != nullptr)
		{
			if (connection.viaCallback)
			{
				AURenderCallbackStruct callback;
				callback.inputProc = nullptr;
				callback.inputProcRefCon = nullptr;
				AudioUnitSetProperty(dest->unit, kAudioUnitProperty_SetRenderCallback,
					kAudioUnitScope_Input, connection.destInputNumber, &callback, sizeof(callback));

				if (connection.context != nullptr)
					connection.context->sourceUnit = nullptr;
			}
			else
			{
				AudioUnitConnection auConnection;
				auConnection.sourceAudioUnit = nullptr;
				auConnection.sourceOutputNumber = 0;
				auConnection.destInputNumber = connection.destInputNumber;
				AudioUnitSetProperty(dest->unit, kAudioUnitProperty_MakeConnection,
					kAudioUnitScope_Input, connection.destInputNumber, &auConnection, sizeof(auConnection));
			}
		}
	}

	graph->connections.erase(graph->connections.begin() + index);
}

static void AUGraphStopInternal(AUGraphData* graph)
{
	for (AUGraphData::Node& node : graph->nodes)
	{
		if (node.unit != nullptr && node.desc.componentType == kAudioUnitType_Output)
			AudioOutputUnitStop(node.unit);
	}
	graph->running = false;
}

static void AUGraphUninitializeInternal(AUGraphData* graph)
{
	if (!graph->initialized)
		return;

	for (AUGraphData::Node& node : graph->nodes)
	{
		if (node.unit != nullptr)
			AudioUnitUninitialize(node.unit);
	}
	graph->initialized = false;
}

static OSStatus AUGraphRemoveNodeInternal(AUGraphData* graph, AUNode node)
{
	size_t index = AUGraphIndexOfNode(graph, node);
	if (index == graph->nodes.size())
		return kAUGraphErr_NodeNotFound;

	for (size_t i = 0; i < graph->connections.size(); )
	{
		if (graph->connections[i].sourceNode == node || graph->connections[i].destNode == node)
			AUGraphRemoveConnection(graph, i);
		else
			i++;
	}

	AUGraphDestroyNodeUnit(graph->nodes[index]);
	graph->nodes.erase(graph->nodes.begin() + index);

	return noErr;
}

// ____________________________________________________________________________
// Public API

OSStatus NewAUGraph(AUGraph* outGraph)
{
	if (outGraph == nullptr)
		return paramErr;

	*outGraph = new AUGraphData();
	return noErr;
}

OSStatus DisposeAUGraph(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	{
		std::lock_guard<std::mutex> lock(inGraph->mutex);

		if (inGraph->running)
			AUGraphStopInternal(inGraph);
		AUGraphUninitializeInternal(inGraph);

		for (AUGraphData::Node& node : inGraph->nodes)
			AUGraphDestroyNodeUnit(node);

		for (ConnectionRenderContext* context : inGraph->contexts)
			delete context;

		inGraph->contexts.clear();
		inGraph->connections.clear();
		inGraph->renderNotifies.clear();
		inGraph->nodes.clear();
		inGraph->open = false;
	}

	delete inGraph;
	return noErr;
}

OSStatus AUGraphAddNode(AUGraph inGraph, const AudioComponentDescription* inDescription, AUNode* outNode)
{
	if (inGraph == nullptr || inDescription == nullptr || outNode == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node node;
	node.id = inGraph->nextNodeId++;
	node.desc = *inDescription;
	node.unit = nullptr;

	inGraph->nodes.push_back(node);

	if (inGraph->open)
	{
		OSStatus status = AUGraphInstantiateNode(inGraph, inGraph->nodes.back());
		if (status != noErr)
		{
			inGraph->nodes.pop_back();
			return status;
		}
	}

	*outNode = node.id;
	return noErr;
}

OSStatus AUGraphRemoveNode(AUGraph inGraph, AUNode inNode)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (inGraph->running)
		return kAUGraphErr_CannotDoInCurrentContext;

	return AUGraphRemoveNodeInternal(inGraph, inNode);
}

OSStatus AUGraphGetNodeCount(AUGraph inGraph, UInt32* outNumberOfNodes)
{
	if (inGraph == nullptr || outNumberOfNodes == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	*outNumberOfNodes = static_cast<UInt32>(inGraph->nodes.size());
	return noErr;
}

OSStatus AUGraphGetIndNode(AUGraph inGraph, UInt32 inIndex, AUNode* outNode)
{
	if (inGraph == nullptr || outNode == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (inIndex >= inGraph->nodes.size())
		return kAUGraphErr_NodeNotFound;

	*outNode = inGraph->nodes[inIndex].id;
	return noErr;
}

OSStatus AUGraphNodeInfo(AUGraph inGraph, AUNode inNode, AudioComponentDescription* outDescription, AudioUnit* outAudioUnit)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node* node = AUGraphFindNode(inGraph, inNode);
	if (node == nullptr)
		return kAUGraphErr_NodeNotFound;

	if (outDescription != nullptr)
		*outDescription = node->desc;
	if (outAudioUnit != nullptr)
		*outAudioUnit = node->unit;

	return noErr;
}

OSStatus AUGraphOpen(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (inGraph->open)
		return noErr;

	for (AUGraphData::Node& node : inGraph->nodes)
	{
		OSStatus status = AUGraphInstantiateNode(inGraph, node);
		if (status != noErr)
			return status;
	}

	inGraph->open = true;
	return noErr;
}

OSStatus AUGraphClose(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (inGraph->running)
		AUGraphStopInternal(inGraph);
	if (inGraph->initialized)
		AUGraphUninitializeInternal(inGraph);

	for (AUGraphData::Node& node : inGraph->nodes)
		AUGraphDestroyNodeUnit(node);

	// Units are gone; connections will have to be re-applied on re-open.
	for (AUGraphData::Connection& connection : inGraph->connections)
	{
		connection.applied = false;
		connection.viaCallback = false;
		connection.context = nullptr;
	}
	for (ConnectionRenderContext* context : inGraph->contexts)
		context->sourceUnit = nullptr;

	inGraph->open = false;
	inGraph->initialized = false;
	inGraph->running = false;
	return noErr;
}

OSStatus AUGraphInitialize(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (!inGraph->open)
		return kAUGraphErr_CannotDoInCurrentContext;
	if (inGraph->initialized)
		return noErr;

	OSStatus status = AUGraphApplyPendingConnections(inGraph);
	if (status != noErr)
		return status;

	for (AUGraphData::Node& node : inGraph->nodes)
	{
		if (node.unit == nullptr)
			continue;
		status = AudioUnitInitialize(node.unit);
		if (status != noErr)
			return status;
	}

	inGraph->initialized = true;
	return noErr;
}

OSStatus AUGraphUninitialize(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (inGraph->running)
		AUGraphStopInternal(inGraph);
	AUGraphUninitializeInternal(inGraph);
	return noErr;
}

OSStatus AUGraphStart(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (!inGraph->initialized)
		return kAUGraphErr_CannotDoInCurrentContext;
	if (inGraph->running)
		return noErr;

	bool foundOutput = false;
	OSStatus firstError = noErr;

	for (AUGraphData::Node& node : inGraph->nodes)
	{
		if (node.unit == nullptr || node.desc.componentType != kAudioUnitType_Output)
			continue;

		foundOutput = true;
		OSStatus status = AudioOutputUnitStart(node.unit);
		if (status != noErr && firstError == noErr)
			firstError = status;
	}

	if (firstError != noErr)
		return firstError;
	if (!foundOutput)
		return kAUGraphErr_OutputNodeErr;

	inGraph->running = true;
	return noErr;
}

OSStatus AUGraphStop(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphStopInternal(inGraph);
	return noErr;
}

OSStatus AUGraphIsOpen(AUGraph inGraph, Boolean* outIsOpen)
{
	if (inGraph == nullptr || outIsOpen == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	*outIsOpen = inGraph->open;
	return noErr;
}

OSStatus AUGraphIsInitialized(AUGraph inGraph, Boolean* outIsInitialized)
{
	if (inGraph == nullptr || outIsInitialized == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	*outIsInitialized = inGraph->initialized;
	return noErr;
}

OSStatus AUGraphIsRunning(AUGraph inGraph, Boolean* outIsRunning)
{
	if (inGraph == nullptr || outIsRunning == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	*outIsRunning = inGraph->running;
	return noErr;
}

OSStatus AUGraphConnectNodeInput(AUGraph inGraph, AUNode inSourceNode, UInt32 inSourceOutputNumber, AUNode inDestNode, UInt32 inDestInputNumber)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node* source = AUGraphFindNode(inGraph, inSourceNode);
	AUGraphData::Node* dest = AUGraphFindNode(inGraph, inDestNode);
	if (source == nullptr || dest == nullptr)
		return kAUGraphErr_NodeNotFound;
	if (inSourceNode == inDestNode)
		return kAUGraphErr_InvalidConnection;

	// Replace any connection already feeding this input.
	for (size_t i = 0; i < inGraph->connections.size(); )
	{
		if (inGraph->connections[i].destNode == inDestNode &&
			inGraph->connections[i].destInputNumber == inDestInputNumber)
			AUGraphRemoveConnection(inGraph, i);
		else
			i++;
	}

	AUGraphData::Connection connection;
	connection.sourceNode = inSourceNode;
	connection.sourceOutputNumber = inSourceOutputNumber;
	connection.destNode = inDestNode;
	connection.destInputNumber = inDestInputNumber;
	connection.applied = false;
	connection.viaCallback = false;
	connection.context = nullptr;

	inGraph->connections.push_back(connection);

	if (source->unit != nullptr && dest->unit != nullptr)
	{
		OSStatus status = AUGraphApplyConnection(inGraph, inGraph->connections.back());
		if (status != noErr)
		{
			inGraph->connections.pop_back();
			return status;
		}
	}

	return noErr;
}

OSStatus AUGraphDisconnectNodeInput(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	size_t index = AUGraphIndexOfConnection(inGraph, inDestNode, inDestInputNumber);
	if (index == inGraph->connections.size())
		return kAUGraphErr_InvalidConnection;

	AUGraphRemoveConnection(inGraph, index);
	return noErr;
}

OSStatus AUGraphSetNodeInputCallback(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber, const AURenderCallbackStruct* inInputCallback)
{
	if (inGraph == nullptr || inInputCallback == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node* node = AUGraphFindNode(inGraph, inDestNode);
	if (node == nullptr)
		return kAUGraphErr_NodeNotFound;

	// A callback and a connection are mutually exclusive on a given input.
	for (size_t i = 0; i < inGraph->connections.size(); )
	{
		if (inGraph->connections[i].destNode == inDestNode &&
			inGraph->connections[i].destInputNumber == inDestInputNumber)
			AUGraphRemoveConnection(inGraph, i);
		else
			i++;
	}

	if (inInputCallback->inputProc != nullptr)
		node->inputCallbacks[inDestInputNumber] = *inInputCallback;
	else
		node->inputCallbacks.erase(inDestInputNumber);

	if (node->unit != nullptr)
	{
		return AudioUnitSetProperty(node->unit, kAudioUnitProperty_SetRenderCallback,
			kAudioUnitScope_Input, inDestInputNumber, inInputCallback, sizeof(*inInputCallback));
	}

	return noErr;
}

OSStatus AUGraphClearConnections(AUGraph inGraph)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	while (!inGraph->connections.empty())
		AUGraphRemoveConnection(inGraph, inGraph->connections.size() - 1);

	return noErr;
}

OSStatus AUGraphGetNumberOfInteractions(AUGraph inGraph, UInt32* outNumInteractions)
{
	if (inGraph == nullptr || outNumInteractions == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	UInt32 count = static_cast<UInt32>(inGraph->connections.size());
	for (AUGraphData::Node& node : inGraph->nodes)
		count += static_cast<UInt32>(node.inputCallbacks.size());

	*outNumInteractions = count;
	return noErr;
}

OSStatus AUGraphGetInteractionInfo(AUGraph inGraph, UInt32 inInteractionIndex, AUNodeInteraction* outInteraction)
{
	if (inGraph == nullptr || outInteraction == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	if (inInteractionIndex < inGraph->connections.size())
	{
		AUGraphData::Connection& connection = inGraph->connections[inInteractionIndex];
		outInteraction->nodeInteractionType = kAUNodeInteraction_Connection;
		outInteraction->nodeInteraction.connection.sourceNode = connection.sourceNode;
		outInteraction->nodeInteraction.connection.sourceOutputNumber = connection.sourceOutputNumber;
		outInteraction->nodeInteraction.connection.destNode = connection.destNode;
		outInteraction->nodeInteraction.connection.destInputNumber = connection.destInputNumber;
		return noErr;
	}

	UInt32 index = inInteractionIndex - static_cast<UInt32>(inGraph->connections.size());

	for (AUGraphData::Node& node : inGraph->nodes)
	{
		for (auto& entry : node.inputCallbacks)
		{
			if (index == 0)
			{
				outInteraction->nodeInteractionType = kAUNodeInteraction_InputCallback;
				outInteraction->nodeInteraction.inputCallback.destNode = node.id;
				outInteraction->nodeInteraction.inputCallback.destInputNumber = entry.first;
				outInteraction->nodeInteraction.inputCallback.cback = entry.second;
				return noErr;
			}
			index--;
		}
	}

	return kAUGraphErr_InvalidConnection;
}

OSStatus AUGraphCountNodeInteractions(AUGraph inGraph, AUNode inNode, UInt32* outNumInteractions)
{
	if (inGraph == nullptr || outNumInteractions == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node* node = AUGraphFindNode(inGraph, inNode);
	if (node == nullptr)
		return kAUGraphErr_NodeNotFound;

	UInt32 count = 0;
	for (AUGraphData::Connection& connection : inGraph->connections)
	{
		if (connection.sourceNode == inNode || connection.destNode == inNode)
			count++;
	}
	count += static_cast<UInt32>(node->inputCallbacks.size());

	*outNumInteractions = count;
	return noErr;
}

OSStatus AUGraphGetNodeInteractions(AUGraph inGraph, AUNode inNode, UInt32* ioNumInteractions, AUNodeInteraction* outInteractions)
{
	if (inGraph == nullptr || ioNumInteractions == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node* node = AUGraphFindNode(inGraph, inNode);
	if (node == nullptr)
		return kAUGraphErr_NodeNotFound;

	UInt32 capacity = *ioNumInteractions;
	if (capacity > 0 && outInteractions == nullptr)
		return paramErr;

	UInt32 count = 0;
	for (AUGraphData::Connection& connection : inGraph->connections)
	{
		if (connection.sourceNode != inNode && connection.destNode != inNode)
			continue;

		if (count < capacity)
		{
			outInteractions[count].nodeInteractionType = kAUNodeInteraction_Connection;
			outInteractions[count].nodeInteraction.connection.sourceNode = connection.sourceNode;
			outInteractions[count].nodeInteraction.connection.sourceOutputNumber = connection.sourceOutputNumber;
			outInteractions[count].nodeInteraction.connection.destNode = connection.destNode;
			outInteractions[count].nodeInteraction.connection.destInputNumber = connection.destInputNumber;
		}
		count++;
	}

	for (auto& entry : node->inputCallbacks)
	{
		if (count < capacity)
		{
			outInteractions[count].nodeInteractionType = kAUNodeInteraction_InputCallback;
			outInteractions[count].nodeInteraction.inputCallback.destNode = node->id;
			outInteractions[count].nodeInteraction.inputCallback.destInputNumber = entry.first;
			outInteractions[count].nodeInteraction.inputCallback.cback = entry.second;
		}
		count++;
	}

	*ioNumInteractions = count;
	return noErr;
}

OSStatus AUGraphUpdate(AUGraph inGraph, Boolean* outIsUpdated)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	OSStatus status = noErr;
	if (inGraph->open)
		status = AUGraphApplyPendingConnections(inGraph);

	if (outIsUpdated != nullptr)
		*outIsUpdated = true;

	return status;
}

OSStatus AUGraphAddRenderNotify(AUGraph inGraph, AURenderCallback inCallback, void* inRefCon)
{
	if (inGraph == nullptr || inCallback == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	inGraph->renderNotifies.push_back(std::make_pair(inCallback, inRefCon));

	for (AUGraphData::Node& node : inGraph->nodes)
	{
		if (node.unit != nullptr && node.desc.componentType == kAudioUnitType_Output)
			AudioUnitAddRenderNotify(node.unit, inCallback, inRefCon);
	}

	return noErr;
}

OSStatus AUGraphRemoveRenderNotify(AUGraph inGraph, AURenderCallback inCallback, void* inRefCon)
{
	if (inGraph == nullptr || inCallback == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	for (size_t i = 0; i < inGraph->renderNotifies.size(); )
	{
		if (inGraph->renderNotifies[i].first == inCallback &&
			inGraph->renderNotifies[i].second == inRefCon)
			inGraph->renderNotifies.erase(inGraph->renderNotifies.begin() + i);
		else
			i++;
	}

	for (AUGraphData::Node& node : inGraph->nodes)
	{
		if (node.unit != nullptr && node.desc.componentType == kAudioUnitType_Output)
			AudioUnitRemoveRenderNotify(node.unit, inCallback, inRefCon);
	}

	return noErr;
}

OSStatus AUGraphGetCPULoad(AUGraph inGraph, Float32* outAverageCPULoad)
{
	if (inGraph == nullptr || outAverageCPULoad == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	*outAverageCPULoad = 0.0f;
	return noErr;
}

OSStatus AUGraphGetMaxCPULoad(AUGraph inGraph, Float32* outMaxLoad)
{
	if (inGraph == nullptr || outMaxLoad == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	*outMaxLoad = 0.0f;
	return noErr;
}

// Deprecated Carbon-style entry points; they simply forward to the AUComponent
// versions.
OSStatus AUGraphNewNode(AUGraph inGraph, const struct ComponentDescription* inDescription, UInt32 inClassDataSize, const void* inClassData, AUNode* outNode)
{
	(void) inClassDataSize;
	(void) inClassData;

	if (inGraph == nullptr || inDescription == nullptr || outNode == nullptr)
		return paramErr;

	AudioComponentDescription description;
	description.componentType = inDescription->componentType;
	description.componentSubType = inDescription->componentSubType;
	description.componentManufacturer = inDescription->componentManufacturer;
	description.componentFlags = inDescription->componentFlags;
	description.componentFlagsMask = inDescription->componentFlagsMask;

	return AUGraphAddNode(inGraph, &description, outNode);
}

OSStatus AUGraphGetNodeInfo(AUGraph inGraph, AUNode inNode, struct ComponentDescription* outDescription, UInt32* outClassDataSize, void** outClassData, AudioUnit* outAudioUnit)
{
	if (inGraph == nullptr)
		return paramErr;

	std::lock_guard<std::mutex> lock(inGraph->mutex);

	AUGraphData::Node* node = AUGraphFindNode(inGraph, inNode);
	if (node == nullptr)
		return kAUGraphErr_NodeNotFound;

	if (outDescription != nullptr)
	{
		outDescription->componentType = node->desc.componentType;
		outDescription->componentSubType = node->desc.componentSubType;
		outDescription->componentManufacturer = node->desc.componentManufacturer;
		outDescription->componentFlags = node->desc.componentFlags;
		outDescription->componentFlagsMask = node->desc.componentFlagsMask;
	}
	if (outClassDataSize != nullptr)
		*outClassDataSize = 0;
	if (outClassData != nullptr)
		*outClassData = nullptr;
	if (outAudioUnit != nullptr)
		*outAudioUnit = node->unit;

	return noErr;
}