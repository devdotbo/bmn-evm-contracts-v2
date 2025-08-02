// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/SimpleEscrow.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/OneInchAdapter.sol";

contract DeployMultiChain is Script {
    struct ChainConfig {
        string name;
        string rpcUrl;
        uint256 chainId;
        address limitOrderProtocol;
    }
    
    struct DeploymentResult {
        uint256 chainId;
        string chainName;
        address factory;
        address adapter;
        bool success;
    }
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Configure chains
        ChainConfig[] memory chains = _getChainConfigs();
        DeploymentResult[] memory results = new DeploymentResult[](chains.length);
        
        // Deploy to each chain
        for (uint256 i = 0; i < chains.length; i++) {
            console.log("========================================");
            console.log("Deploying to", chains[i].name, "...");
            console.log("Chain ID:", chains[i].chainId);
            
            try vm.createSelectFork(chains[i].rpcUrl) {
                require(block.chainid == chains[i].chainId, "Chain ID mismatch");
                
                vm.startBroadcast(deployerPrivateKey);
                
                // Deploy SimpleEscrowFactory with deterministic address
                bytes32 salt = keccak256(abi.encodePacked("BMN_FACTORY_V2", chains[i].chainId));
                SimpleEscrowFactory factory = new SimpleEscrowFactory{salt: salt}(address(0));
                
                address adapterAddress;
                if (chains[i].limitOrderProtocol != address(0)) {
                    // Deploy OneInchAdapter with deterministic address
                    bytes32 adapterSalt = keccak256(abi.encodePacked("BMN_ADAPTER_V2", chains[i].chainId));
                    OneInchAdapter adapter = new OneInchAdapter{salt: adapterSalt}(
                        address(factory),
                        chains[i].limitOrderProtocol
                    );
                    adapterAddress = address(adapter);
                    
                    // Set adapter in factory
                    factory.setOneInchAdapter(adapterAddress);
                }
                
                vm.stopBroadcast();
                
                // Save result
                results[i] = DeploymentResult({
                    chainId: chains[i].chainId,
                    chainName: chains[i].name,
                    factory: address(factory),
                    adapter: adapterAddress,
                    success: true
                });
                
                console.log("[SUCCESS] Successfully deployed to", chains[i].name);
                console.log("Factory:", address(factory));
                console.log("Adapter:", adapterAddress);
                
                // Save individual deployment
                _saveChainDeployment(chains[i].chainId, address(factory), adapterAddress);
                
            } catch Error(string memory reason) {
                console.log("[ERROR] Failed to deploy to", chains[i].name);
                console.log("Reason:", reason);
                results[i] = DeploymentResult({
                    chainId: chains[i].chainId,
                    chainName: chains[i].name,
                    factory: address(0),
                    adapter: address(0),
                    success: false
                });
            }
        }
        
        // Save summary
        _saveSummary(results);
        
        // Print summary
        console.log("========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("========================================");
        for (uint256 i = 0; i < results.length; i++) {
            if (results[i].success) {
                console.log("[SUCCESS]", results[i].chainName, "- Factory:", results[i].factory);
            } else {
                console.log("[ERROR]", results[i].chainName, "- FAILED");
            }
        }
    }
    
    function _getChainConfigs() internal view returns (ChainConfig[] memory) {
        ChainConfig[] memory chains = new ChainConfig[](4);
        
        // Ethereum Mainnet / Sepolia
        chains[0] = ChainConfig({
            name: "Ethereum",
            rpcUrl: vm.envOr("ETH_RPC_URL", string("https://eth.llamarpc.com")),
            chainId: vm.envOr("ETH_CHAIN_ID", uint256(1)),
            limitOrderProtocol: 0x1111111254EEB25477B68fb85Ed929f73A960582
        });
        
        // Polygon
        chains[1] = ChainConfig({
            name: "Polygon",
            rpcUrl: vm.envOr("POLYGON_RPC_URL", string("https://polygon.llamarpc.com")),
            chainId: vm.envOr("POLYGON_CHAIN_ID", uint256(137)),
            limitOrderProtocol: 0x1111111254EEB25477B68fb85Ed929f73A960582
        });
        
        // Arbitrum
        chains[2] = ChainConfig({
            name: "Arbitrum",
            rpcUrl: vm.envOr("ARBITRUM_RPC_URL", string("https://arbitrum.llamarpc.com")),
            chainId: vm.envOr("ARBITRUM_CHAIN_ID", uint256(42161)),
            limitOrderProtocol: 0x1111111254EEB25477B68fb85Ed929f73A960582
        });
        
        // Base
        chains[3] = ChainConfig({
            name: "Base",
            rpcUrl: vm.envOr("BASE_RPC_URL", string("https://base.llamarpc.com")),
            chainId: vm.envOr("BASE_CHAIN_ID", uint256(8453)),
            limitOrderProtocol: 0x1111111254EEB25477B68fb85Ed929f73A960582
        });
        
        return chains;
    }
    
    function _saveChainDeployment(
        uint256 chainId,
        address factory,
        address adapter
    ) internal {
        string memory json = "deployment";
        vm.serializeAddress(json, "factory", factory);
        vm.serializeAddress(json, "adapter", adapter);
        vm.serializeUint(json, "chainId", chainId);
        string memory output = vm.serializeUint(json, "timestamp", block.timestamp);
        
        string memory filename = string.concat(
            "./deployments/",
            vm.toString(chainId),
            "-deployment.json"
        );
        vm.writeJson(output, filename);
    }
    
    function _saveSummary(DeploymentResult[] memory results) internal {
        string memory json = "summary";
        
        // Serialize each result
        for (uint256 i = 0; i < results.length; i++) {
            string memory chainJson = string.concat("chain_", vm.toString(i));
            vm.serializeUint(chainJson, "chainId", results[i].chainId);
            vm.serializeString(chainJson, "name", results[i].chainName);
            vm.serializeAddress(chainJson, "factory", results[i].factory);
            vm.serializeAddress(chainJson, "adapter", results[i].adapter);
            string memory chainOutput = vm.serializeBool(chainJson, "success", results[i].success);
            vm.serializeString(json, string.concat("chain_", vm.toString(i)), chainOutput);
        }
        
        string memory output = vm.serializeUint(json, "timestamp", block.timestamp);
        vm.writeJson(output, "./deployments/multi-chain-summary.json");
        console.log("Multi-chain deployment summary saved");
    }
}