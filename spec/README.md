# Running Tests

## Using rspec

All tests should be run using `bundle exec rspec`

```bash
# Run all tests
bundle exec rspec

# Run with fail-fast (stop on first failure)
bundle exec rspec --fail-fast

# For verbose output
DEBUG=1 bundle exec rspec

# Show zero coverage lines
SHOW_ZERO_COVERAGE=1 bundle exec rspec

# Run single spec file at exact line number
DEBUG=1 bundle exec rspec spec/path/to/spec_file.rb:10
```

## RSpec Testing Guidelines

### Core Philosophy: Behavior Verification vs. Implementation Coupling

The fundamental principle of refactoring-resistant testing is the distinction between **what** a system does (Behavior) and **how** it does it (Implementation).

- **Behavior:** Defined by the Public Contract—the inputs accepted by the System Under Test (SUT) and the observable outputs or side effects it produces at its architectural boundaries.
- **Implementation:** Encompasses internal control flow, private helper methods, auxiliary data structures, and the specific sequence of internal operations.

> **Principle:** True refactoring resistance is achieved only when the test suite is agnostic to the SUT's internal composition.

When a test couples itself to implementation details—for instance, by asserting that a specific private method was called or by mocking an internal helper—it violates encapsulation. Such tests verify that the code *looks* a certain way, not that it *works*. This leads to **"False Negatives"** or **"Fragile Tests,"** where a test fails simply because a developer renamed a private method or optimized a loop, even though the business logic remains correct.

### Core Principles

- **Always assume RSpec has been integrated** - Never edit `spec_helper.rb` or add new testing gems
- **Test Behavior, Not Implementation** - Verify the public contract, not internal structure
- **Refactoring Resistance** - Tests should survive internal refactoring without modification
- Keep test scope minimal - start with the most crucial and essential tests
- Never test features that are built into Ruby or external gems
- Never write tests for performance unless specifically requested
- Isolate external dependencies (HTTP calls, file system, time) at architectural boundaries only

### Test Type Selection

#### Unit Specs (`spec/status_mcp/`)

- Use for: Library classes, modules, service objects, utility methods
- Test: Public API behavior, error handling, edge cases
- Example: Testing `StatusMcp::Server` tools, data loading

### Testing Workflow

1. **Plan First**: Think carefully about what tests should be written for the given scope/feature
2. **Review Existing Tests**: Check existing specs before creating new test data
3. **Isolate Dependencies**: Use mocks/stubs for external services (HTTP, file system, time)
4. **Use WebMock**: Set up WebMock for HTTP calls to external services
5. **Minimal Scope**: Start with essential tests, add edge cases only when specifically requested
6. **DRY Principles**: Review `spec/support/` for existing shared examples and helpers before duplicating code

### The Mocking Policy: Architectural Boundaries Only

To enforce refactoring resistance, strict controls must be placed on the use of Test Doubles (mocks, stubs, spies).

#### 🚫 STRICTLY FORBIDDEN: Internal Mocks

The policy unequivocally prohibits the mocking of internals. This prohibition covers:

1. **Mocking Private/Protected Methods:**
   - Attempts to mock private methods are fundamentally flawed
   - These methods exist solely to organize code; they do not represent a contract
   - If a test mocks a private method, it is coupled to the signature of that method

2. **Partial Mocks (Spies on the SUT):**
   - Creating a real instance of the SUT but overriding one of its methods
   - This creates a "Frankenstein" object that exists only in the test environment

3. **Reflection-Based State Manipulation:**
   - Using reflection to set private fields to bypass validation logic
   - This tests a state that might be unreachable in the actual application

#### ✅ PERMITTED MOCKS: Architectural Boundaries

Mocking is reserved exclusively for **Architectural Boundaries**—the seams where the SUT interacts with systems it does not own or control.

| Boundary Type | Examples | Rationale for Mocking | Preferred Double |
| :--- | :--- | :--- | :--- |
| **Persistence Layer** | File I/O (data.json) | Eliminates dependency on file system; speed/isolation | Fake (In-Memory) or Stub |
| **External I/O** | HTTP Clients | Prevents network calls; simulates error states | Mock or Stub |
| **File System** | Disk Access | Decouples tests from slow/stateful disk | Fake (Virtual FS) |

### The Input Derivation Protocol

When tempted to mock an internal method to "force" code execution, **STOP**. Instead, use the **Input Derivation Protocol**.

#### Protocol Mechanics

Treat the SUT as a logic puzzle. To execute a specific line of code, solve the logical equation defined by the control flow graph leading to it.

1. **Analyze the Logic (Path Predicate Analysis):**
   - Examine the conditional checks (`if`, `guard clauses`)
   - *Example:* `if results.empty?: ...`

2. **Reverse Engineer the Input:**
   - Determine the initial state that satisfies the predicate
   - *Result:* Input data must have matching services

3. **Construct Data (The Fixture):**
   - Create a data fixture that naturally satisfies the conditions
   ```ruby
   mock_data = [{"name" => "Example Service", "links" => {...}}]
   ```

4. **Execute via Public API:**
   - Pass the constructed input into the public entry point

### Test Data Management

#### Test Doubles and Mocks

- Use verifying doubles (`instance_double`, `class_double`) for external dependencies **only**
- Create test data inline for simple cases
- **Never mock methods within the class you're testing**

#### Let/Let! Usage

- **`let`**: Lazy evaluation - only creates when accessed; use by default
- **`let!`**: Eager evaluation - creates immediately; use when laziness causes issues
- Keep `let` blocks close to where they're used
- Avoid creating unused data with `let!`

### Isolation Best Practices

#### When to Isolate

- File I/O (reading data.json) → stub or use in-memory data
- HTTP calls (in update_status_list script) → use WebMock
- Nondeterminism (time, UUIDs) → stub to deterministic values

#### When NOT to Isolate

- Simple Ruby operations
- Cheap internal collaborations
- JSON parsing/generation

#### Isolation Techniques

- **Verifying Doubles**: Prefer `instance_double(Class)`, `class_double` over plain `double`
- **Stubs**: `allow(obj).to receive(:method).and_return(value)` for replacing behavior
- **WebMock**: Stub HTTP requests for external services
- **File Stubs**: `allow(File).to receive(:read).and_return(json_data)`

#### Isolation Rules

1. **Preserve Public Behavior**: Test via public API, never test private methods directly
2. **Mock Only Boundaries**: Only mock external dependencies (HTTP, File System), never internal methods
3. **Scope Narrowly**: Keep stubs local to examples; avoid global state
4. **Use Verifying Doubles**: Prefer `instance_double`, `class_double` over plain doubles
5. **Default to WebMock for HTTP**: Stub HTTP requests to avoid external dependencies
6. **Assert Outcomes**: Focus on behavior, not internal call choreography
7. **Input Derivation**: When you need to test a specific code path, derive the input that naturally triggers it

### WebMock Configuration

- WebMock is configured in `spec/spec_helper.rb`
- Stub HTTP requests to avoid external dependencies in tests
- Use `stub_request` to mock HTTP responses

### Testing File Operations

When testing classes that read data.json:

```ruby
RSpec.describe StatusMcp::Server::SearchServicesTool do
  let(:mock_data) do
    [
      {
        "name" => "Example Service",
        "links" => {
          "official_status" => "https://status.example.com"
        }
      }
    ]
  end
  
  before do
    # ✅ Mocking file I/O (architectural boundary) is allowed
    allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
    allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(mock_data))
  end
  
  it "searches services by name" do
    tool = described_class.new
    result = tool.call(query: "Example")
    
    expect(result).to include("Example Service")
  end
end
```

### Testing Error Handling

Always test error cases:

```ruby
it "returns message when no services found" do
  tool = described_class.new
  result = tool.call(query: "Nonexistent")
  
  expect(result).to include("No services found")
end
```

### Code Examples: Anti-Patterns vs. Best Practices

#### 🔴 Bad Practice: Targeted Mocking (Internal Mocks)

```ruby
# ❌ DO NOT DO THIS
RSpec.describe StatusMcp::Server::SearchServicesTool do
  it "formats service output" do
    tool = described_class.new
    
    # VIOLATION: Mocking a method inside the SUT
    allow(tool).to receive(:format_service).and_return("formatted")
    
    result = tool.call(query: "Example")
    expect(result).to eq("formatted")
  end
end
```

#### 🟢 Best Practice: Input Driven

```ruby
# ✅ DO THIS
RSpec.describe StatusMcp::Server::SearchServicesTool do
  let(:mock_data) do
    [{"name" => "Example Service", "links" => {"official_status" => "https://status.example.com"}}]
  end
  
  before do
    allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
    allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(mock_data))
  end
  
  it "searches and formats services" do
    tool = described_class.new
    result = tool.call(query: "Example")
    
    # Assert behavior (what it returns), not implementation
    expect(result).to include("Example Service")
    expect(result).to include("https://status.example.com")
  end
end
```

### Anti-Patterns to Avoid

- **Mocking Internal Methods:** Never mock private/protected methods or methods within the class you're testing
- **Partial Mocks:** Never create partial mocks of the SUT
- **Testing Implementation Details:** Don't assert that specific private methods were called
- **Not Isolating Boundaries:** Always isolate external dependencies (File I/O)
- **Testing Ruby/Gem Functionality:** Don't test features built into Ruby or external gems
- **Creating Unnecessary Data:** Avoid creating unused test data with `let!`

### Self-Correction Checklist

Before committing, perform this audit:

1. **Ownership Check:** Am I mocking a method that belongs to the class I am testing? (If YES → Delete mock)
2. **Verification Target:** Am I testing that the code works, or how the code works?
3. **Input Integrity:** Did I create the necessary input data to reach the code path naturally?
4. **Refactoring Resilience:** If I rename private helper methods, will this test still pass?
5. **Boundary Check:** Is the mock representing a true I/O boundary (File, HTTP)?
6. **Public API:** Am I testing through the public interface only?

### Summary: The Refactoring-Resistant Testing Matrix

| Feature | Strict Mocking (Recommended) | Targeted Mocking (Prohibited) |
| :--- | :--- | :--- |
| **Primary Focus** | Public Contract / Behavior | Internal Implementation |
| **Private Methods** | Ignored (Opaque Box) | Mocked / Spied / Tested Directly |
| **Refactoring Safety** | High (Implementation agnostic) | Low (Coupled to structure) |
| **Bug Detection** | High (Verifies logic integration) | Mixed (Misses integration issues) |
| **Maintenance Cost** | Low (Survives changes) | High (Requires updates on refactor) |
| **Architectural Impact** | Encourages Decoupling & DI | Encourages Tightly Coupled Code |
