# Multi-Agent Orchestration and Handoff Documentation

## Overview

The Zava AI Shopping Assistant implements a sophisticated **multi-agent orchestration system** that routes customer queries to specialized AI agents based on intent detection. This architecture ensures customers receive expert assistance tailored to their specific needs, whether they're looking for product recommendations, checking inventory, calculating loyalty discounts, or modifying room designs.

## Handoff Mechanism Architecture

### Core Components

The handoff system consists of three primary layers:

1. **Intent Detection Layer** - Powered by the Phi-4 model
2. **Agent Selection Layer** - Routes to appropriate specialized agent
3. **Execution Layer** - Processes requests through selected agent

### The Handoff Process Flow

When a customer message arrives through the WebSocket connection in `chat_app.py`, the system follows this orchestrated flow:

```
Customer Message → Handoff Agent (Phi-4) → Agent Selection → Specialized Agent → Response
```

The handoff logic begins at **line 553** in chat_app.py:

1. **Context Formatting**: The conversation history is formatted and cleaned of any previously flagged content
2. **Handoff Call**: The Phi-4 model analyzes the context using the prompt from `handoffPrompt.txt`
3. **Agent Selection**: Based on the handoff response, the appropriate agent is selected
4. **Agent Execution**: The selected agent processes the request with its specialized capabilities

### Handoff Prompt Engineering

The `handoffPrompt.txt` file contains carefully crafted multi-shot examples that train the Phi-4 model to recognize patterns:

- Product queries → `interior_designer`
- Image editing requests → `interior_designer_create_image`
- Inventory checks → `inventory_agent`
- Loyalty/discount queries → `customer_loyalty`
- General greetings/cart operations → `cora`

## Agent Roles and Responsibilities

### 1. **Cora Agent** - The Friendly Concierge
**Agent ID**: Stored in environment variable `cora`

**Primary Responsibilities:**
- Initial customer greetings and general assistance
- Cart management operations (add/remove/update items)
- Order checkout coordination
- Store location information (defaults to Miami store, 2.5 miles away)
- Closing conversations gracefully

**Prompt Location**: `ShopperAgentPrompt.txt` and `CoraPrompt.txt`

**Special Behavior**: 
- Returns minimal JSON responses with empty product arrays
- Maintains conversational context to avoid repetitive greetings
- Executed through a fallback mechanism using the Phi-4 model (lines 796-808 in chat_app.py)

### 2. **Interior Designer Agent** - The Creative Consultant
**Agent ID**: Stored in environment variable `interior_designer`

**Primary Responsibilities:**
- Product recommendations based on customer needs
- Room design consultations
- Paint coverage calculations
- Accessory upselling (sprayers, tape, drop cloths)
- Visual content analysis (images/videos)

**Tools Available:**
- `product_recommendations` - Searches product catalog via Azure AI Search
- `create_image` - Generates modified room visualizations (when `interior_designer_create_image` is selected)

**Prompt Location**: `InteriorDesignAgentPrompt.txt`

**Execution Modes:**

a) **Text-only queries** (lines 686-711):
   - Fetches relevant products using AI Search
   - Formats response with product recommendations

b) **Image-based queries** (lines 714-743):
   - Analyzes uploaded images for context
   - Provides tailored recommendations based on visual input
   - Automatically suggests paint accessories

c) **Image creation mode** (lines 765-793):
   - Triggered when `interior_designer_create_image` is selected
   - Modifies room images based on user preferences
   - Limited to predefined color hexcodes for brand consistency

### 3. **Inventory Agent** - The Stock Manager
**Agent ID**: Stored in environment variable `inventory_agent`

**Primary Responsibilities:**
- Real-time inventory checking
- Stock availability status reporting
- Location-based inventory information
- Bulk availability queries

**Tools Available:**
- `inventory_check` - Simulates Microsoft Fabric data source queries

**Prompt Location**: `InventoryAgentPrompt.txt`

**Input Format Example:**
```python
product_dict = {'Standard Paint Tray': 'PROD0045', 'Premium Roller': 'PROD0013'}
```

### 4. **Customer Loyalty Agent** - The Rewards Specialist
**Agent ID**: Stored in environment variable `customer_loyalty`

**Primary Responsibilities:**
- Customer identification and verification
- Discount calculation based on loyalty tiers
- Personalized reward messaging
- Retention-focused pricing strategies

**Tools Available:**
- `calculate_discount` - Complex discount logic considering:
  - Customer tenure
  - Lifetime value
  - Churn likelihood
  - Loyalty tier (Platinum/Gold/Silver/Bronze)

**Prompt Location**: `CustomerLoyaltyAgentPrompt.txt`

**Discount Tiers:**
- Tier 1: 0-5%
- Tier 2: 5-7.5%
- Tier 3: 7.5-10%
- Tier 4: 10-12.5%
- Tier 5: 12.5-15%
- Tier 6: 15-20%
- Tier 7: 20-25% (maximum)

## Special Orchestration Scenarios

### Cart Operations Parallel Processing

When the word "cart" appears in a message (line 586-641 in chat_app.py), the system executes **parallel operations**:

1. **Cart Update Task**: Analyzes full conversation history to determine cart contents
2. **Cora Response Task**: Generates friendly conversational response

These run concurrently using `asyncio.gather()` for optimal performance, then results are merged using the `merge_cart_and_cora` utility function.

### Content Filter Handling

The handoff system includes sophisticated error handling for content policy violations (lines 568-581):

1. Detects filter triggers in error messages
2. Adds problematic prompts to a `bad_prompts` set
3. Automatically redacts flagged content from future context
4. Returns user-friendly error messages

### Session-Persistent State

The orchestration maintains several session-level variables:

- **`persistent_cart`**: Shopping cart state across interactions
- **`session_discount_percentage`**: Loyalty discount for the session
- **`persistent_image_url`**: Last uploaded image for context
- **`image_cache`**: Cached image descriptions to avoid redundant processing
- **`bad_prompts`**: Set of prompts that triggered content filters

## Agent Communication Patterns

### Synchronous Pattern (Standard Agents)
```python
AgentProcessor → Project Client → Azure AI Agent → Tool Execution → Response
```

Used by: Inventory Agent, Customer Loyalty Agent

### Asynchronous Streaming Pattern
```python
AgentProcessor → Stream Generator → Chunked Responses → Frontend
```

Enables real-time response streaming for better UX

### Fallback Pattern (Cora and Interior Designer)
```python
Direct LLM Call → Response Parsing → JSON Formatting → Frontend
```

Used when agents need direct model access without Azure AI Agent framework

## Performance Optimizations

### Caching Strategies

1. **Image Description Cache**: Stores analyzed image descriptions to avoid redundant vision model calls
2. **Toolset Cache**: Reuses agent tool configurations (in agent_processor.py)
3. **Pre-fetching**: Asynchronously analyzes images before they're needed

### Parallel Execution

- Thread pool executor with 4 workers for CPU-bound operations
- Concurrent cart and response generation
- Asynchronous image pre-fetching

### Optimized Serialization

- Uses `orjson` library (2-3x faster than standard JSON)
- Optimized string formatting for message construction
- Deque with maxlen for memory-efficient history management

## Monitoring and Observability

Every major orchestration step is instrumented:

```python
[TIMING] 14:32:15.234 - Handoff Processing: 0.523s | Reply length: 18 chars
[TIMING] 14:32:15.445 - Agent Selection: 0.021s | Selected: interior_designer
[TIMING] 14:32:16.234 - Agent Execution: 0.789s | Agent: interior_designer
```

OpenTelemetry spans track:
- Handoff call duration
- Agent selection logic
- Tool execution times
- End-to-end request processing

## Error Recovery and Resilience

The orchestration includes multiple fallback mechanisms:

1. **Agent Failure**: Falls back to simple error message
2. **Tool Failure**: Agent continues without tool result
3. **Content Filter**: Removes problematic content and retries
4. **WebSocket Disconnect**: Graceful session cleanup
5. **Invalid JSON**: Safe parsing with fallback values

## Configuration and Deployment

All agent IDs and endpoints are managed through environment variables in the `.env` file:

```env
interior_designer="asst_S0PIL5ZZOb9CyCWiadkpMhOx"
customer_loyalty="asst_sAa4dkCN6n73gB5bERX2Rwaw"
inventory_agent="asst_YdVXdXzaPBWLsXIAhsTbIFTv"
cora="asst_mEoWe6sDOYBAMluTi1r4nia3"
```

This design enables:
- Easy agent swapping for A/B testing
- Environment-specific configurations
- Automated deployment through CI/CD pipelines

## Future Extensibility

The orchestration architecture supports:

1. **New Agent Integration**: Add new agent types by extending the handoff prompt and selection logic
2. **Dynamic Routing**: Implement ML-based routing instead of rule-based
3. **Agent Collaboration**: Enable agents to consult each other
4. **Feedback Loops**: Incorporate user satisfaction to improve routing
5. **Multi-Modal Agents**: Support for audio/video processing agents

The modular design ensures that new capabilities can be added without disrupting existing functionality, making the system highly maintainable and scalable for future business requirements.