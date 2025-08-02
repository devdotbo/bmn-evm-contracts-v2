// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ISimpleEscrow {
    // Events
    event EscrowFunded(address indexed sender, uint256 amount, uint256 timestamp);
    event EscrowWithdrawn(address indexed recipient, bytes32 preimage, uint256 timestamp);
    event EscrowRefunded(address indexed sender, uint256 amount, uint256 timestamp);

    // Errors
    error InvalidToken();
    error InvalidSender();
    error InvalidRecipient();
    error InvalidHashlock();
    error InvalidTimelock();
    error InvalidAmount();
    error UnauthorizedSender();
    error AlreadyFunded();
    error NotFunded();
    error AlreadyWithdrawn();
    error AlreadyRefunded();
    error InvalidPreimage();
    error TimelockNotExpired();
    error TimelockExpired();

    // View functions
    function token() external view returns (address);
    function sender() external view returns (address);
    function recipient() external view returns (address);
    function hashlock() external view returns (bytes32);
    function timelock() external view returns (uint256);
    function amount() external view returns (uint256);
    function funded() external view returns (bool);
    function withdrawn() external view returns (bool);
    function refunded() external view returns (bool);
    function preimage() external view returns (bytes32);

    function getDetails() external view returns (
        address _token,
        address _sender,
        address _recipient,
        uint256 _amount,
        bytes32 _hashlock,
        uint256 _timelock,
        bool _funded,
        bool _withdrawn,
        bool _refunded,
        bytes32 _preimage
    );

    function canWithdraw() external view returns (bool);
    function canRefund() external view returns (bool);

    // State-changing functions
    function fund(uint256 _amount) external;
    function withdraw(bytes32 _preimage) external;
    function refund() external;
}