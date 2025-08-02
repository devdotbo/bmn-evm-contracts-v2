import { 
  createPublicClient, 
  createWalletClient, 
  http, 
  parseEther,
  parseUnits,
  formatUnits,
  encodeAbiParameters,
  keccak256,
  type Address,
  type Hash,
  type Hex,
  type Abi
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { config } from "./config.ts";

// Logger utility
class Logger {
  private logFile: string;
  
  constructor(logFile: string) {
    this.logFile = logFile;
    // Reset log file
    Deno.writeTextFileSync(this.logFile, `Atomic Swap Test Log - ${new Date().toISOString()}\n${"=".repeat(80)}\n\n`);
  }
  
  log(message: string, data?: any) {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ${message}${data ? '\n' + JSON.stringify(data, null, 2) : ''}\n`;
    console.log(logEntry);
    Deno.writeTextFileSync(this.logFile, logEntry, { append: true });
  }
  
  error(message: string, error: any) {
    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ERROR: ${message}\n${error.stack || error.message || error}\n`;
    console.error(logEntry);
    Deno.writeTextFileSync(this.logFile, logEntry, { append: true });
  }
}

// ABI loader
async function loadABI(contractName: string): Promise<Abi> {
  try {
    const abiPath = `./abis/${contractName}.abi.json`;
    const abiContent = await Deno.readTextFile(abiPath);
    return JSON.parse(abiContent) as Abi;
  } catch (error) {
    // Fallback to out directory if abis directory doesn't exist
    try {
      const outPath = `../out/${contractName}.sol/${contractName}.json`;
      const outContent = await Deno.readTextFile(outPath);
      const parsed = JSON.parse(outContent);
      return parsed.abi as Abi;
    } catch {
      throw new Error(`Failed to load ABI for ${contractName}: ${error}`);
    }
  }
}

// Deployment loader
async function loadDeployment(chainId: number): Promise<{factory: Address, adapter?: Address, usdc?: Address, xtz?: Address}> {
  try {
    const deploymentPath = `../deployments/${chainId}-deployment.json`;
    const content = await Deno.readTextFile(deploymentPath);
    return JSON.parse(content);
  } catch {
    // Return default addresses for local testing
    console.log(`No deployment file found for chain ${chainId}, using default addresses`);
    return {
      factory: "0x5FbDB2315678afecb367f032d93F642f64180aa3" as Address,
      usdc: "0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512" as Address,
      xtz: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0" as Address
    };
  }
}

// Utility functions
async function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function retry<T>(
  fn: () => Promise<T>,
  retries: number = config.retryAttempts,
  delay: number = config.retryDelay
): Promise<T> {
  for (let i = 0; i < retries; i++) {
    try {
      return await fn();
    } catch (error) {
      if (i === retries - 1) throw error;
      await sleep(delay);
    }
  }
  throw new Error("Retry failed");
}

// Main atomic swap test
async function testAtomicSwap() {
  const logger = new Logger("../logs/atomic-swap.log");
  logger.log("Starting Atomic Swap Test");
  logger.log("Configuration", {
    baseRpc: config.baseRpc,
    etherlinkRpc: config.etherlinkRpc,
    baseChainId: config.baseChainId,
    etherlinkChainId: config.etherlinkChainId
  });
  
  // Test accounts
  const alice = privateKeyToAccount(config.alicePrivateKey);
  const bob = privateKeyToAccount(config.bobPrivateKey);
  
  logger.log("Test Accounts", {
    alice: alice.address,
    bob: bob.address
  });
  
  // Create clients
  const basePublicClient = createPublicClient({
    transport: http(config.baseRpc),
    chain: {
      id: config.baseChainId,
      name: 'Base Local',
      network: 'base-local',
      nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
      rpcUrls: {
        default: { http: [config.baseRpc] },
        public: { http: [config.baseRpc] }
      }
    }
  });
  
  const etherlinkPublicClient = createPublicClient({
    transport: http(config.etherlinkRpc),
    chain: {
      id: config.etherlinkChainId,
      name: 'Etherlink Local',
      network: 'etherlink-local',
      nativeCurrency: { name: 'Tez', symbol: 'XTZ', decimals: 18 },
      rpcUrls: {
        default: { http: [config.etherlinkRpc] },
        public: { http: [config.etherlinkRpc] }
      }
    }
  });
  
  const baseWalletClient = createWalletClient({
    account: alice,
    transport: http(config.baseRpc),
    chain: basePublicClient.chain
  });
  
  const etherlinkWalletClient = createWalletClient({
    account: bob,
    transport: http(config.etherlinkRpc),
    chain: etherlinkPublicClient.chain
  });
  
  try {
    // Load ABIs
    logger.log("Loading contract ABIs...");
    const [ERC20_ABI, FACTORY_ABI, ESCROW_ABI] = await Promise.all([
      loadABI("MockERC20"),
      loadABI("SimpleEscrowFactory"),
      loadABI("SimpleEscrow")
    ]);
    
    // Load deployment addresses
    logger.log("Loading deployment addresses...");
    const baseDeployment = await loadDeployment(config.baseChainId);
    const etherlinkDeployment = await loadDeployment(config.etherlinkChainId);
    
    const factoryAddressBase = baseDeployment.factory;
    const factoryAddressEtherlink = etherlinkDeployment.factory;
    const usdcAddress = baseDeployment.usdc!;
    const xtzAddress = etherlinkDeployment.xtz!;
    
    logger.log("Contract Addresses", {
      base: {
        factory: factoryAddressBase,
        usdc: usdcAddress
      },
      etherlink: {
        factory: factoryAddressEtherlink,
        xtz: xtzAddress
      }
    });
    
    // Deploy mock tokens if needed
    logger.log("Setting up test tokens...");
    
    // Check if we need to deploy tokens
    const usdcCode = await basePublicClient.getBytecode({ address: usdcAddress });
    if (!usdcCode || usdcCode === '0x') {
      logger.log("USDC not deployed, deploying mock token...");
      // In a real scenario, we'd deploy here
      throw new Error("Mock tokens not deployed. Please run deployment script first.");
    }
    
    // Mint USDC to Alice on Base
    await retry(async () => {
      await baseWalletClient.writeContract({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: "mint",
        args: [alice.address, parseUnits("1000", 6)] // 1000 USDC
      });
    });
    
    // Mint XTZ to Bob on Etherlink
    await retry(async () => {
      await etherlinkWalletClient.writeContract({
        address: xtzAddress,
        abi: ERC20_ABI,
        functionName: "mint",
        args: [bob.address, parseUnits("100", 18)] // 100 XTZ
      });
    });
    
    await sleep(2000); // Wait for transactions to be mined
    
    // Check balances
    const aliceUsdcBalance = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    const bobXtzBalance = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    logger.log("Initial Balances", {
      aliceUsdc: formatUnits(aliceUsdcBalance, 6),
      bobXtz: formatUnits(bobXtzBalance, 18)
    });
    
    // Generate atomic swap parameters
    const preimage = keccak256("0x" + "atomicswapsecret123".split("").map(c => c.charCodeAt(0).toString(16).padStart(2, "0")).join("")) as Hex;
    const hashlock = keccak256(encodeAbiParameters([{ type: "bytes32" }], [preimage]));
    const timelock = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now
    const salt = keccak256("0x" + Date.now().toString(16)) as Hex;
    
    logger.log("Swap Parameters", {
      preimage,
      hashlock,
      timelock: timelock.toString(),
      salt
    });
    
    // Swap amounts
    const usdcAmount = parseUnits("100", 6); // 100 USDC
    const xtzAmount = parseUnits("10", 18); // 10 XTZ
    
    logger.log("=== STEP 1: Alice creates escrow on Base ===");
    
    // Alice approves USDC
    await retry(async () => {
      await baseWalletClient.writeContract({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [factoryAddressBase, usdcAmount]
      });
    });
    await sleep(2000);
    
    // Alice creates escrow on Base
    const createEscrowTx = await retry(async () => {
      return await baseWalletClient.writeContract({
        address: factoryAddressBase,
        abi: FACTORY_ABI,
        functionName: "createEscrowWithFunding",
        args: [
          usdcAddress,
          alice.address,
          bob.address,
          hashlock,
          timelock,
          salt,
          usdcAmount
        ]
      });
    });
    
    logger.log("Alice created escrow on Base", { tx: createEscrowTx });
    await sleep(3000);
    
    // Get escrow address
    const baseEscrowAddress = await basePublicClient.readContract({
      address: factoryAddressBase,
      abi: FACTORY_ABI,
      functionName: "computeEscrowAddress",
      args: [usdcAddress, alice.address, bob.address, hashlock, timelock, salt]
    });
    
    logger.log("Base escrow address", { escrow: baseEscrowAddress });
    
    // Verify escrow details
    const baseEscrowDetails = await basePublicClient.readContract({
      address: baseEscrowAddress,
      abi: ESCROW_ABI,
      functionName: "getDetails"
    });
    
    logger.log("Base escrow details", baseEscrowDetails);
    
    logger.log("=== STEP 2: Bob creates escrow on Etherlink ===");
    
    // Simulate Bob seeing Alice's escrow and creating corresponding one
    await sleep(2000);
    
    // Bob approves XTZ
    await retry(async () => {
      await etherlinkWalletClient.writeContract({
        address: xtzAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [factoryAddressEtherlink, xtzAmount]
      });
    });
    await sleep(2000);
    
    // Bob creates escrow on Etherlink with same hashlock
    const bobSalt = keccak256("0x" + (Date.now() + 1).toString(16)) as Hex;
    const createEscrowTx2 = await retry(async () => {
      return await etherlinkWalletClient.writeContract({
        address: factoryAddressEtherlink,
        abi: FACTORY_ABI,
        functionName: "createEscrowWithFunding",
        args: [
          xtzAddress,
          bob.address,
          alice.address,
          hashlock, // Same hashlock!
          timelock,
          bobSalt,
          xtzAmount
        ]
      });
    });
    
    logger.log("Bob created escrow on Etherlink", { tx: createEscrowTx2 });
    await sleep(3000);
    
    // Get Etherlink escrow address
    const etherlinkEscrowAddress = await etherlinkPublicClient.readContract({
      address: factoryAddressEtherlink,
      abi: FACTORY_ABI,
      functionName: "computeEscrowAddress",
      args: [xtzAddress, bob.address, alice.address, hashlock, timelock, bobSalt]
    });
    
    logger.log("Etherlink escrow address", { escrow: etherlinkEscrowAddress });
    
    logger.log("=== STEP 3: Alice reveals preimage on Etherlink ===");
    
    // Simulate Alice waiting and then revealing
    await sleep(3000);
    
    // Alice withdraws on Etherlink using the preimage
    const aliceEtherlinkWallet = createWalletClient({
      account: alice,
      transport: http(config.etherlinkRpc),
      chain: etherlinkPublicClient.chain
    });
    
    const withdrawTx = await retry(async () => {
      return await aliceEtherlinkWallet.writeContract({
        address: etherlinkEscrowAddress,
        abi: ESCROW_ABI,
        functionName: "withdraw",
        args: [preimage]
      });
    });
    
    logger.log("Alice withdrew on Etherlink", { tx: withdrawTx });
    await sleep(3000);
    
    // Check Alice's XTZ balance
    const aliceXtzBalance = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    logger.log("Alice received XTZ", { balance: formatUnits(aliceXtzBalance, 18) });
    
    logger.log("=== STEP 4: Bob uses preimage on Base ===");
    
    // Bob can now see the preimage from the Etherlink escrow
    const etherlinkDetails = await etherlinkPublicClient.readContract({
      address: etherlinkEscrowAddress,
      abi: ESCROW_ABI,
      functionName: "getDetails"
    });
    
    const revealedPreimage = etherlinkDetails.preimage;
    logger.log("Bob found preimage", { preimage: revealedPreimage });
    
    // Bob withdraws on Base using the revealed preimage
    const bobBaseWallet = createWalletClient({
      account: bob,
      transport: http(config.baseRpc),
      chain: basePublicClient.chain
    });
    
    const withdrawTx2 = await retry(async () => {
      return await bobBaseWallet.writeContract({
        address: baseEscrowAddress,
        abi: ESCROW_ABI,
        functionName: "withdraw",
        args: [revealedPreimage]
      });
    });
    
    logger.log("Bob withdrew on Base", { tx: withdrawTx2 });
    await sleep(3000);
    
    // Check Bob's USDC balance
    const bobUsdcBalance = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    logger.log("Bob received USDC", { balance: formatUnits(bobUsdcBalance, 6) });
    
    logger.log("=== STEP 5: Verify final balances ===");
    
    // Check all final balances
    const finalAliceUsdc = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    const finalAliceXtz = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [alice.address]
    });
    
    const finalBobUsdc = await basePublicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    const finalBobXtz = await etherlinkPublicClient.readContract({
      address: xtzAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [bob.address]
    });
    
    logger.log("Final Balances", {
      alice: {
        usdc: formatUnits(finalAliceUsdc, 6),
        xtz: formatUnits(finalAliceXtz, 18)
      },
      bob: {
        usdc: formatUnits(finalBobUsdc, 6),
        xtz: formatUnits(finalBobXtz, 18)
      }
    });
    
    // Verify swap success
    const swapSuccess = 
      finalAliceUsdc < aliceUsdcBalance && // Alice sent USDC
      finalAliceXtz > 0n && // Alice received XTZ
      finalBobUsdc > 0n && // Bob received USDC
      finalBobXtz < bobXtzBalance; // Bob sent XTZ
    
    if (swapSuccess) {
      logger.log("✅ ATOMIC SWAP COMPLETED SUCCESSFULLY!");
      logger.log("Summary", {
        aliceSentUsdc: formatUnits(aliceUsdcBalance - finalAliceUsdc, 6),
        aliceReceivedXtz: formatUnits(finalAliceXtz, 18),
        bobSentXtz: formatUnits(bobXtzBalance - finalBobXtz, 18),
        bobReceivedUsdc: formatUnits(finalBobUsdc, 6)
      });
    } else {
      logger.error("❌ ATOMIC SWAP FAILED!", { swapSuccess });
    }
    
  } catch (error) {
    logger.error("Test failed", error);
    throw error;
  }
}

// Run the test
if (import.meta.main) {
  testAtomicSwap().catch(console.error);
}