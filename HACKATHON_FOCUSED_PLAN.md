# Hackathon-Focused Implementation Plan: Get It Working!

## 🎯 Hackathon Priority: Working Demo in Limited Time

### What We Need (In Order)
1. ✅ **1inch-compatible interfaces** that work
2. ✅ **Simplified contracts** that deploy and execute
3. ✅ **Working resolver** for Alice & Bob
4. ✅ **Two chains running** with successful swaps
5. ✅ **Lightning Network integration** as the cherry on top

### What We DON'T Need
- ❌ Complex gas optimizations
- ❌ Production-grade security audits  
- ❌ Perfect code coverage
- ❌ Extensive documentation
- ❌ Multiple deployment environments

## 📋 Phase 1: Simplified Contracts (3-4 hours)

### SimpleEscrow.sol - Just Make It Work
```solidity
// KISS - Keep It Simple, Stupid!
contract SimpleEscrow {
    address public token;
    uint256 public amount;
    address public sender;
    address public recipient;
    bytes32 public hashlock;
    uint256 public timelock;
    bool public withdrawn;
    bool public refunded;
    bytes32 public preimage;
    
    // Just the essentials
    function fund() external;
    function withdraw(bytes32 _preimage) external;
    function refund() external;
}
```

### SimpleEscrowFactory.sol - Direct Creation
```solidity
contract SimpleEscrowFactory {
    // Both direct and 1inch paths
    function createEscrow(...) returns (address);
    function createEscrowFrom1inchOrder(...) returns (address);
    function computeEscrowAddress(...) returns (address);
}
```

### OneInchAdapter.sol - Minimal Integration
```solidity
// Just enough to trigger escrow creation from 1inch orders
contract OneInchAdapter is BaseExtension {
    function _postInteraction(...) {
        // Extract data, create escrow, done!
    }
}
```

## 📋 Phase 2: Update Resolver (2-3 hours)

### Quick Resolver Updates
1. **Update Contract ABIs** - Point to new simplified contracts
2. **Simplify State Management** - Remove complex timelock logic
3. **Update Order Monitoring** - Work with new events
4. **Test with Local Chains** - Make sure it detects and executes

### Key Changes in bmn-evm-resolver:
```typescript
// Update to work with SimpleEscrow instead of complex system
class SimplifiedResolver {
    // Monitor for escrow creation
    async monitorEscrows();
    
    // Check profitability (keep simple)
    async isProfitable();
    
    // Execute atomic swap
    async executeSwap();
}
```

## 📋 Phase 3: Get Two Chains Running (1-2 hours)

### Local Testing Setup
```bash
# Simple two-chain setup
anvil --chain-id 1 --port 8545 &  # "Ethereum"
anvil --chain-id 137 --port 8546 & # "Polygon"

# Deploy contracts
forge script DeploySimple.s.sol --rpc-url http://localhost:8545
forge script DeploySimple.s.sol --rpc-url http://localhost:8546

# Run Alice on chain 1
deno task alice:create-order

# Run Bob (resolver) monitoring both chains
deno task resolver:start
```

### Success Criteria
- ✅ Alice creates order with atomic swap data
- ✅ Bob sees order and creates escrows
- ✅ Both parties fund their escrows
- ✅ Bob withdraws with secret
- ✅ Alice withdraws with revealed secret
- ✅ Complete atomic swap!

## 📋 Phase 4: Lightning Network Integration (3-4 hours)

### Lightning Atomic Swap Architecture
```
EVM Chain A ←→ Lightning Network ←→ EVM Chain B
    ↓               ↓                    ↓
SimpleEscrow    HTLC Invoice      SimpleEscrow
```

### Key Components for Lightning

#### 1. LightningAdapter.sol
```solidity
contract LightningAdapter {
    // Bridge between EVM escrow and Lightning HTLC
    mapping(bytes32 => LightningSwap) public swaps;
    
    struct LightningSwap {
        address escrow;
        bytes32 paymentHash;
        uint256 amount;
        bool settled;
    }
    
    function initiateLightningSwap(bytes32 paymentHash, uint256 amount);
    function settleLightningPayment(bytes32 preimage);
}
```

#### 2. Lightning Node Integration
```typescript
// In resolver - add Lightning support
class LightningResolver {
    // Connect to LND/CLN node
    async connectToLightningNode();
    
    // Create Lightning invoice with same hash
    async createHTLCInvoice(paymentHash, amount);
    
    // Monitor for payment and reveal preimage
    async monitorLightningPayment();
    
    // Bridge settlement to EVM
    async bridgeSettlement(preimage);
}
```

#### 3. Flow for EVM ↔ Lightning ↔ EVM
1. Alice locks funds in EVM escrow (Chain A)
2. Bob creates Lightning invoice with same hash
3. Alice pays Lightning invoice
4. Lightning reveals preimage to Bob
5. Bob uses preimage to claim EVM escrow
6. Complete cross-chain atomic swap!

### Lightning Integration Steps
1. **Set up local Lightning nodes** (use Polar for easy setup)
2. **Create Lightning adapter contract**
3. **Update resolver with Lightning monitoring**
4. **Test EVM → Lightning → EVM flow**
5. **Demo the three-way atomic swap**

## 🚀 Hackathon Demo Script

### Demo Flow (10 minutes)
1. **Introduction** (1 min)
   - Problem: Bridging is risky
   - Solution: Atomic swaps with 1inch + Lightning

2. **EVM ↔ EVM Demo** (3 min)
   - Show 1inch order creation
   - Show automatic escrow deployment
   - Execute successful swap
   - Highlight simplicity vs V1

3. **Lightning Integration Demo** (4 min)
   - Show Lightning node setup
   - Create EVM → Lightning swap
   - Show invoice payment
   - Complete three-way swap

4. **Benefits & Future** (2 min)
   - No bridge risk
   - 1inch ecosystem compatible
   - Lightning Network expansion
   - True cross-chain interoperability

## 📝 Minimal Documentation Needed

### 1. README.md
```markdown
# Bridge-Me-Not V2: 1inch + Lightning Atomic Swaps

## Quick Start
1. Deploy contracts: `forge script Deploy.s.sol`
2. Run resolver: `deno task resolver`
3. Create swap: `deno task alice:swap`

## Lightning Setup
1. Install Polar
2. Start Lightning nodes
3. Run Lightning resolver
```

### 2. DEMO_GUIDE.md
- Step-by-step demo instructions
- Common issues & fixes
- Key talking points

## ⏱️ Time Allocation

| Task | Time | Priority |
|------|------|----------|
| Simplify contracts | 3-4h | HIGH |
| Update resolver | 2-3h | HIGH |
| Test two chains | 1-2h | HIGH |
| Lightning integration | 3-4h | MEDIUM |
| Demo preparation | 1h | HIGH |
| **Total** | **10-14h** | - |

## 🎯 Success Metrics for Hackathon

1. **It Works** - Can complete atomic swap end-to-end
2. **1inch Compatible** - Orders work through 1inch protocol
3. **Lightning Demo** - At least one successful Lightning swap
4. **Live Demo** - No crashes during presentation
5. **Clear Value Prop** - Judges understand the innovation

## 🚨 Hackathon Shortcuts (It's OK!)

- Use `forge script` for quick deployments (not production ready)
- Hardcode some values if needed for demo
- Skip extensive error handling (just don't crash)
- Use simple retry logic instead of complex recovery
- Focus on happy path for demo

## 🏁 Final Checklist

Before demo:
- [ ] Contracts deployed on 2+ chains
- [ ] Resolver running and detecting orders
- [ ] Can complete EVM ↔ EVM swap
- [ ] Lightning nodes connected
- [ ] Can complete EVM ↔ Lightning swap
- [ ] Demo script rehearsed
- [ ] Backup plan if something fails

Remember: **Done is better than perfect!** Focus on a working demo that shows the core innovation of combining 1inch atomic swaps with Lightning Network.