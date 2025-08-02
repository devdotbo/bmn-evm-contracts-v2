// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/SimpleEscrowFactory.sol";
import "../src/OneInchAdapter.sol";
import "../src/LightningBridge.sol";

contract Verify is Script {
    struct ContractInfo {
        address addr;
        string name;
        bytes constructorArgs;
    }
    
    function run() external {
        // Load deployment addresses from JSON
        uint256 chainId = block.chainid;
        string memory deploymentPath = string.concat(
            "./deployments/",
            vm.toString(chainId),
            "-deployment.json"
        );
        
        // Check if deployment file exists
        if (!vm.exists(deploymentPath)) {
            console.log("[ERROR] No deployment file found for chain", chainId);
            return;
        }
        
        string memory deploymentData = vm.readFile(deploymentPath);
        
        // Extract addresses
        address factory = vm.parseJsonAddress(deploymentData, ".factory");
        address adapter = vm.parseJsonAddress(deploymentData, ".adapter");
        
        // Check for Lightning deployment
        string memory lightningPath = string.concat(
            "./deployments/",
            vm.toString(chainId),
            "-lightning-deployment.json"
        );
        address bridge;
        if (vm.exists(lightningPath)) {
            string memory lightningData = vm.readFile(lightningPath);
            bridge = vm.parseJsonAddress(lightningData, ".bridge");
        }
        
        console.log("========================================");
        console.log("VERIFYING CONTRACTS ON CHAIN", chainId);
        console.log("========================================");
        
        // Prepare verification data
        ContractInfo[] memory contracts = _prepareContracts(factory, adapter, bridge);
        
        // Verify each contract
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i].addr == address(0)) continue;
            
            console.log("Verifying", contracts[i].name, "at", contracts[i].addr);
            
            // Generate verification command
            string memory cmd = _generateVerifyCommand(
                contracts[i].addr,
                contracts[i].name,
                contracts[i].constructorArgs
            );
            
            console.log("Run this command to verify:");
            console.log(cmd);
            console.log("");
        }
        
        // Save verification script
        _saveVerificationScript(contracts);
    }
    
    function _prepareContracts(
        address factory,
        address adapter,
        address bridge
    ) internal view returns (ContractInfo[] memory) {
        ContractInfo[] memory contracts = new ContractInfo[](3);
        
        // SimpleEscrowFactory (no constructor args)
        contracts[0] = ContractInfo({
            addr: factory,
            name: "SimpleEscrowFactory",
            constructorArgs: ""
        });
        
        // OneInchAdapter
        if (adapter != address(0)) {
            // Get 1inch protocol address from environment or use mainnet default
            address limitOrderProtocol = vm.envOr(
                "LIMIT_ORDER_PROTOCOL",
                address(0x1111111254EEB25477B68fb85Ed929f73A960582)
            );
            
            contracts[1] = ContractInfo({
                addr: adapter,
                name: "OneInchAdapter",
                constructorArgs: abi.encode(factory, limitOrderProtocol)
            });
        }
        
        // LightningBridge
        if (bridge != address(0)) {
            address resolver = vm.envAddress("RESOLVER_ADDRESS");
            
            contracts[2] = ContractInfo({
                addr: bridge,
                name: "LightningBridge",
                constructorArgs: abi.encode(factory, resolver)
            });
        }
        
        return contracts;
    }
    
    function _generateVerifyCommand(
        address contractAddress,
        string memory contractName,
        bytes memory constructorArgs
    ) internal view returns (string memory) {
        string memory basePath = "src/";
        string memory contractPath = string.concat(basePath, contractName, ".sol");
        
        // Build forge verify-contract command
        string[] memory inputs = new string[](20);
        uint256 idx = 0;
        
        inputs[idx++] = "forge";
        inputs[idx++] = "verify-contract";
        inputs[idx++] = vm.toString(contractAddress);
        inputs[idx++] = string.concat(contractPath, ":", contractName);
        inputs[idx++] = "--chain";
        inputs[idx++] = vm.toString(block.chainid);
        
        // Add constructor args if present
        if (constructorArgs.length > 0) {
            inputs[idx++] = "--constructor-args";
            inputs[idx++] = vm.toString(constructorArgs);
        }
        
        // Add etherscan API key
        inputs[idx++] = "--etherscan-api-key";
        inputs[idx++] = "$ETHERSCAN_API_KEY";
        
        // Add verbosity
        inputs[idx++] = "-vvv";
        
        // Trim array to actual size
        string[] memory finalInputs = new string[](idx);
        for (uint256 i = 0; i < idx; i++) {
            finalInputs[i] = inputs[i];
        }
        
        // Join command parts
        return _joinStrings(finalInputs, " ");
    }
    
    function _joinStrings(string[] memory parts, string memory separator) internal pure returns (string memory) {
        if (parts.length == 0) return "";
        
        string memory result = parts[0];
        for (uint256 i = 1; i < parts.length; i++) {
            result = string.concat(result, separator, parts[i]);
        }
        return result;
    }
    
    function _saveVerificationScript(ContractInfo[] memory contracts) internal {
        string memory script = "#!/bin/bash\n\n";
        script = string.concat(script, "# Contract verification script for chain ", vm.toString(block.chainid), "\n");
        script = string.concat(script, "# Generated on ", vm.toString(block.timestamp), "\n\n");
        script = string.concat(script, "set -e\n\n");
        
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i].addr == address(0)) continue;
            
            script = string.concat(script, "echo \"Verifying ", contracts[i].name, "...\"\n");
            script = string.concat(
                script,
                _generateVerifyCommand(contracts[i].addr, contracts[i].name, contracts[i].constructorArgs),
                "\n\n"
            );
        }
        
        script = string.concat(script, "echo \"[SUCCESS] All contracts verified!\"\n");
        
        string memory filename = string.concat(
            "./deployments/verify-",
            vm.toString(block.chainid),
            ".sh"
        );
        vm.writeFile(filename, script);
        
        console.log("Verification script saved to:", filename);
    }
    
    // Helper function to manually verify if automated verification fails
    function verifyManual() external view {
        console.log("========================================");
        console.log("MANUAL VERIFICATION STEPS");
        console.log("========================================");
        console.log("");
        console.log("1. Flatten the contract:");
        console.log("   forge flatten src/SimpleEscrowFactory.sol > SimpleEscrowFactory_flat.sol");
        console.log("");
        console.log("2. Remove duplicate SPDX licenses and pragma statements");
        console.log("");
        console.log("3. Go to Etherscan and verify manually with:");
        console.log("   - Compiler: 0.8.23");
        console.log("   - Optimizer: Enabled (200 runs)");
        console.log("   - License: MIT");
        console.log("");
    }
}