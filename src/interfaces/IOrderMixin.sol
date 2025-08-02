// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/**
 * @title IOrderMixin
 * @notice Interface for 1inch order structure compatibility
 */
interface IOrderMixin {
    struct Order {
        uint256 salt;
        address makerAsset;
        address takerAsset;
        address maker;
        address receiver;
        address allowedSender;
        uint256 makingAmount;
        uint256 takingAmount;
        uint256 offsets;
        bytes interactions;
    }
}