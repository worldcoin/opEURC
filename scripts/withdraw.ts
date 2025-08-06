import { ethers } from "ethers";
import dotenv from "dotenv";

dotenv.config();

// Contract configuration
const L2_BRIDGE_ADAPTER = "0xFC7503C4a6280a7b848B3725703D6690Ef96E122";
const L2_TOKEN_ADDRESS = "0xac354ba7f7cb0a27c1a555ae19b7f544b881f053";
const RECIPIENT_ADDRESS = "0x6348A4a4dF173F68eB28A452Ca6c13493e447aF1";

const L2_RPC_URL = "https://worldchain.drpc.org";
const PRIVATE_KEY = process.env.PRIVATE_KEY;

// Contract ABI - only including the sendMessage function
const CONTRACT_ABI = [
  {
    inputs: [
      {
        internalType: "address",
        name: "_to",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amount",
        type: "uint256",
      },
      {
        internalType: "uint32",
        name: "_minGasLimit",
        type: "uint32",
      },
    ],
    name: "sendMessage",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
];

async function initiateMessageSend() {
  try {
    // Create provider
    const provider = new ethers.JsonRpcProvider(L2_RPC_URL);

    // Create wallet
    const wallet = new ethers.Wallet(PRIVATE_KEY!, provider);

    // ERC20 ABI
    const ERC20_ABI = [
      "function approve(address spender, uint256 amount) returns (bool)",
    ];

    // 1 EURC, 6 decimals
    // const amount = ethers.formatUnits("1", 6);
    const amount = "1"

    const tokenContract = new ethers.Contract(
      L2_TOKEN_ADDRESS,
      ERC20_ABI,
      wallet
    );

    const approveTx = await tokenContract.approve(L2_BRIDGE_ADAPTER, amount);
    await approveTx.wait();

    console.log("Approval tx", approveTx.hash);

    await new Promise(resolve => setTimeout(resolve, 10000));

    // Create contract instance
    const contract = new ethers.Contract(
      L2_BRIDGE_ADAPTER,
      CONTRACT_ABI,
      wallet
    );

    // Function parameters
    const minGasLimit = 1000000; // Minimum gas limit

    // Call the function
    const tx = await contract.sendMessage(
      RECIPIENT_ADDRESS,
      amount,
      minGasLimit
    );
    await tx.wait();

    console.log("Transaction confirmed!", tx.hash);
  } catch (error) {
    console.error("Error calling sendMessage:", error);
  }
}


// Execute the function
initiateMessageSend().then(() => {
  console.log("Withdraw transaction sent successfully");
});

// Withdraw TX

// https://worldscan.org/tx/0x672ccb3790f8e92fa9ad51f66c58f37b49fcd92775126da574a62300e97fd761

// Wait 7 days

// Finalize withdrawal message