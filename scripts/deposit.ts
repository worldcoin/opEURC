import { ethers } from "ethers";
import dotenv from "dotenv";

dotenv.config();

// Contract configuration
const L1_BRIDGE_ADAPTER = "0x795d3c3FCFD43A54D4D6198c796A485f557a3095";
const L1_TOKEN_ADDRESS = "0x1abaea1f7c830bd89acc67ec4af516284b1bc33c";
const RECIPIENT_ADDRESS = "0x6348A4a4dF173F68eB28A452Ca6c13493e447aF1";

const L1_RPC_URL = "https://eth.blockrazor.xyz";
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

async function callSendMessage() {
  try {
    // Create provider
    const provider = new ethers.JsonRpcProvider(L1_RPC_URL);

    // Create wallet
    const wallet = new ethers.Wallet(PRIVATE_KEY!, provider);

    // ERC20 ABI
    const ERC20_ABI = [
      "function approve(address spender, uint256 amount) returns (bool)",
    ];

    // 1 EURC, 6 decimals
    const amount = ethers.formatUnits("1", 6);

    const tokenContract = new ethers.Contract(
      L1_TOKEN_ADDRESS,
      ERC20_ABI,
      wallet
    );

    const approveTx = await tokenContract.approve(L1_BRIDGE_ADAPTER, amount);
    await approveTx.wait();

    console.log("Approval tx", approveTx.hash);

    // Create contract instance
    const contract = new ethers.Contract(
      L1_BRIDGE_ADAPTER,
      CONTRACT_ABI,
      wallet
    );

    const minGasLimit = 1000000;
    
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
callSendMessage().then(() => {
  console.log("Deposit transaction sent successfully");
});
