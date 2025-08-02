# SimpleEscrow Contract Specification

## Overview
SimpleEscrow is a minimalist Hash Time Locked Contract (HTLC) that handles atomic swaps with maximum simplicity. It works for both source and destination chains, eliminating the need for separate contract types.

## Design Principles
- Single unified contract for both source and destination
- No complex state machines or phases
- Standard Solidity types only
- Minimal gas consumption
- Clear and predictable behavior

## Contract State Variables

### Immutable Variables (Set at Creation)
```solidity
address public immutable token;      // ERC20 token to be swapped
address public immutable sender;     // Party who deposits funds
address public immutable recipient;  // Party who can withdraw with preimage
bytes32 public immutable hashlock;   // Hash of the secret preimage
uint256 public immutable timelock;   // Timestamp after which sender can refund
```

### Mutable State Variables
```solidity
uint256 public amount;              // Amount of tokens locked
bool public funded;                 // Whether escrow has been funded
bool public withdrawn;              // Whether funds have been withdrawn
bool public refunded;              // Whether funds have been refunded
bytes32 public preimage;           // Revealed secret (after withdrawal)
```

## Constructor
```solidity
constructor(
    address _token,
    address _sender,
    address _recipient,
    bytes32 _hashlock,
    uint256 _timelock
)
```

### Parameters
- `_token`: ERC20 token contract address
- `_sender`: Address that will fund the escrow
- `_recipient`: Address that can withdraw with correct preimage
- `_hashlock`: keccak256 hash of the secret preimage
- `_timelock`: Unix timestamp after which refund is allowed

### Validation
- All addresses must be non-zero
- Timelock must be in the future
- Hashlock must be non-zero

## Core Functions

### fund(uint256 _amount)
Allows the sender to deposit tokens into the escrow.

**Access Control**: Only callable by sender
**State Requirements**: 
- Not already funded
- Amount must be greater than 0

**Effects**:
- Transfers tokens from sender to contract
- Sets amount and funded = true
- Emits EscrowFunded event

### withdraw(bytes32 _preimage)
Allows recipient to claim tokens by revealing the preimage.

**Access Control**: Callable by anyone (but only recipient receives funds)
**State Requirements**:
- Must be funded
- Not already withdrawn or refunded
- Current time must be before timelock
- keccak256(abi.encode(_preimage)) must equal hashlock

**Effects**:
- Stores the revealed preimage
- Transfers tokens to recipient
- Sets withdrawn = true
- Emits EscrowWithdrawn event

### refund()
Allows sender to reclaim tokens after timeout.

**Access Control**: Only callable by sender
**State Requirements**:
- Must be funded
- Not already withdrawn or refunded
- Current time must be at or after timelock

**Effects**:
- Transfers tokens back to sender
- Sets refunded = true
- Emits EscrowRefunded event

## View Functions

### getDetails()
Returns all escrow details in a single call for easy querying.

**Returns**:
```solidity
struct EscrowDetails {
    address token;
    address sender;
    address recipient;
    bytes32 hashlock;
    uint256 timelock;
    uint256 amount;
    bool funded;
    bool withdrawn;
    bool refunded;
    bytes32 preimage;
}
```

### canWithdraw()
Checks if withdrawal is currently possible.

**Returns**: bool indicating if withdraw can be called successfully

### canRefund()
Checks if refund is currently possible.

**Returns**: bool indicating if refund can be called successfully

## Events

### EscrowFunded
```solidity
event EscrowFunded(
    address indexed sender,
    uint256 amount,
    address token
);
```

### EscrowWithdrawn
```solidity
event EscrowWithdrawn(
    address indexed recipient,
    bytes32 preimage,
    uint256 amount
);
```

### EscrowRefunded
```solidity
event EscrowRefunded(
    address indexed sender,
    uint256 amount
);
```

## Security Considerations

### Reentrancy Protection
- Use OpenZeppelin's ReentrancyGuard on fund, withdraw, and refund functions
- Follow checks-effects-interactions pattern

### Token Safety
- Use OpenZeppelin's SafeERC20 for all token transfers
- Handle tokens that don't return bool on transfer

### Timestamp Considerations
- Add small buffer (e.g., 5 minutes) for cross-chain timestamp differences
- Document that timelock is based on block.timestamp

### Preimage Storage
- Store preimage after successful withdrawal for cross-chain verification
- Preimage is public, allowing other chain to observe and use it

## Gas Optimizations
- Pack bool variables into single storage slot
- Use immutable for all constructor parameters
- Minimal validation to reduce gas costs
- Events use indexed parameters for efficient filtering

## Integration Notes

### For Direct Usage
```solidity
// Create escrow
SimpleEscrow escrow = new SimpleEscrow(token, alice, bob, hashlock, timelock);

// Fund it
token.approve(address(escrow), amount);
escrow.fund(amount);

// Withdraw with preimage
escrow.withdraw(preimage);
```

### For Factory Usage
- Factory deploys with CREATE2 for deterministic addresses
- Factory can call fund() after deployment if tokens are pre-approved

### For Cross-Chain Coordination
- Same hashlock used on both chains
- Shorter timelock on destination chain
- Monitor WithdrawEvent to get revealed preimage

## Testing Checklist
- [ ] Successful funding by sender
- [ ] Successful withdrawal with correct preimage
- [ ] Failed withdrawal with incorrect preimage
- [ ] Successful refund after timeout
- [ ] Failed refund before timeout
- [ ] Only sender can fund
- [ ] Only sender can refund
- [ ] Anyone can call withdraw (but funds go to recipient)
- [ ] Cannot double-spend (withdraw + refund)
- [ ] Cannot fund twice
- [ ] Handles token transfer failures gracefully

## Deployment Considerations
- Deploy with CREATE2 for predictable addresses across chains
- Verify source code on all deployed chains
- Consider proxy pattern for upgradability (though adds complexity)