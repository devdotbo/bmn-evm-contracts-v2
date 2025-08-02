// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IOrderMixin.sol";

interface ISimpleEscrowFactory {
    // Events
    event EscrowCreated(
        address indexed escrow,
        address indexed sender,
        address indexed recipient,
        address token,
        bytes32 hashlock,
        uint256 timelock,
        uint256 chainId,
        bytes32 salt
    );
    
    event EscrowCreatedFrom1inch(
        address indexed escrow,
        bytes32 indexed orderHash,
        address indexed maker,
        address taker
    );

    // Errors
    error InvalidParameters();
    error EscrowAlreadyExists();
    error UnauthorizedAdapter();
    error CreateFailed();
    error TransferFailed();

    // Structs
    struct EscrowParams {
        address token;
        address sender;
        address recipient;
        bytes32 hashlock;
        uint256 timelock;
    }

    struct BatchEscrowParams {
        EscrowParams params;
        bytes32 salt;
    }

    // View functions
    function deployedEscrows(address escrow) external view returns (bool);
    function escrowCount() external view returns (uint256);
    function oneInchAdapter() external view returns (address);
    
    function computeEscrowAddress(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt
    ) external view returns (address);

    function getEscrowBytecode(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock
    ) external pure returns (bytes memory);

    function isEscrowDeployed(address escrow) external view returns (bool);
    
    function getEscrowDetails(address escrow) external view returns (
        address token,
        address sender,
        address recipient,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock,
        bool funded,
        bool withdrawn,
        bool refunded,
        bytes32 preimage
    );

    // State-changing functions
    function createEscrow(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt
    ) external returns (address escrow);

    function createEscrowWithFunding(
        address token,
        address sender,
        address recipient,
        bytes32 hashlock,
        uint256 timelock,
        bytes32 salt,
        uint256 amount
    ) external returns (address escrow);

    function createEscrowFrom1inchOrder(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount
    ) external returns (address escrow);

    function batchCreateEscrows(
        BatchEscrowParams[] calldata escrows
    ) external returns (address[] memory);

    function setOneInchAdapter(address _adapter) external;
}