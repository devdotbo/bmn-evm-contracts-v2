// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../src/interfaces/IOrderMixin.sol";
import "../../src/BaseExtension.sol";

/**
 * @title MockLimitOrderProtocol
 * @dev Basic mock of 1inch LimitOrderProtocol for testing OneInchAdapter
 */
contract MockLimitOrderProtocol {
    using SafeERC20 for IERC20;

    // ===== EVENTS =====

    event OrderFilled(
        bytes32 indexed orderHash,
        uint256 makingAmount,
        uint256 takingAmount
    );

    event OrderCanceled(bytes32 indexed orderHash);

    // ===== STATE VARIABLES =====

    mapping(bytes32 => uint256) public remainingMakingAmount;
    mapping(bytes32 => bool) public cancelledOrders;

    // ===== CORE FUNCTIONS =====

    /**
     * @dev Fill an order (simplified mock implementation)
     * @param order Order to fill
     * @param signature Order signature (ignored in mock)
     * @param extension Extension data for post-interaction
     * @param makingAmount Amount of maker asset to fill
     * @param takingAmount Amount of taker asset to fill
     */
    function fillOrder(
        IOrderMixin.Order calldata order,
        bytes calldata signature,
        bytes calldata extension,
        uint256 makingAmount,
        uint256 takingAmount
    ) external {
        // Silence unused parameter warnings
        signature;

        bytes32 orderHash = hashOrder(order);
        
        require(!cancelledOrders[orderHash], "Order cancelled");
        require(makingAmount > 0, "Making amount must be positive");
        require(takingAmount > 0, "Taking amount must be positive");

        // Simple validation - in real implementation would be more complex
        require(makingAmount <= order.makingAmount, "Making amount too high");
        require(takingAmount <= order.takingAmount, "Taking amount too high");

        // Update remaining amount
        if (remainingMakingAmount[orderHash] == 0) {
            remainingMakingAmount[orderHash] = order.makingAmount;
        }
        
        require(remainingMakingAmount[orderHash] >= makingAmount, "Insufficient remaining amount");
        remainingMakingAmount[orderHash] -= makingAmount;

        // Transfer tokens
        IERC20(order.makerAsset).safeTransferFrom(order.maker, msg.sender, makingAmount);
        IERC20(order.takerAsset).safeTransferFrom(msg.sender, order.receiver != address(0) ? order.receiver : order.maker, takingAmount);

        // Call post-interaction if extension address is provided
        if (hasPostInteraction(order.offsets) && extension.length >= 20) {
            address extensionAddress = extractExtensionAddress(extension);
            if (extensionAddress != address(0)) {
                // Transfer maker tokens to extension contract for processing
                IERC20(order.makerAsset).safeTransfer(extensionAddress, makingAmount);
                
                IPostInteraction(extensionAddress).postInteraction(
                    order,
                    extension[20:], // Skip address bytes
                    orderHash,
                    msg.sender,
                    makingAmount,
                    takingAmount,
                    remainingMakingAmount[orderHash],
                    ""
                );
            }
        }

        emit OrderFilled(orderHash, makingAmount, takingAmount);
    }

    /**
     * @dev Cancel an order
     * @param order Order to cancel
     */
    function cancelOrder(IOrderMixin.Order calldata order) external {
        require(msg.sender == order.maker, "Only maker can cancel");
        
        bytes32 orderHash = hashOrder(order);
        cancelledOrders[orderHash] = true;
        
        emit OrderCanceled(orderHash);
    }

    /**
     * @dev Get remaining amount for an order
     * @param order Order to check
     * @return remainingAmount Remaining making amount
     */
    function remaining(IOrderMixin.Order calldata order) external view returns (uint256 remainingAmount) {
        bytes32 orderHash = hashOrder(order);
        remainingAmount = remainingMakingAmount[orderHash];
        return remainingAmount == 0 ? order.makingAmount : remainingAmount;
    }

    // ===== INTERNAL FUNCTIONS =====

    /**
     * @dev Hash an order
     * @param order Order to hash
     * @return orderHash Hash of the order
     */
    function hashOrder(IOrderMixin.Order calldata order) public pure returns (bytes32) {
        return keccak256(abi.encode(
            order.salt,
            order.makerAsset,
            order.takerAsset,
            order.maker,
            order.receiver,
            order.allowedSender,
            order.makingAmount,
            order.takingAmount,
            order.offsets,
            order.interactions
        ));
    }

    /**
     * @dev Check if order has post-interaction enabled
     * @param offsets Order offsets containing flags
     * @return bool True if post-interaction is enabled
     */
    function hasPostInteraction(uint256 offsets) internal pure returns (bool) {
        // Simplified - check bit flag for post-interaction in offsets
        return (offsets & 0x1) != 0;
    }

    /**
     * @dev Extract extension address from extension data
     * @param extension Extension data
     * @return extensionAddress Address extracted from extension
     */
    function extractExtensionAddress(bytes calldata extension) internal pure returns (address) {
        if (extension.length < 20) return address(0);
        return address(bytes20(extension[0:20]));
    }

    // ===== HELPER FUNCTIONS FOR TESTING =====

    /**
     * @dev Set remaining amount for an order (for testing)
     * @param orderHash Hash of the order
     * @param amount Remaining amount to set
     */
    function setRemainingAmount(bytes32 orderHash, uint256 amount) external {
        remainingMakingAmount[orderHash] = amount;
    }

    /**
     * @dev Force cancel an order (for testing)
     * @param orderHash Hash of the order
     */
    function forceCancelOrder(bytes32 orderHash) external {
        cancelledOrders[orderHash] = true;
        emit OrderCanceled(orderHash);
    }

    /**
     * @dev Build offsets with post-interaction flag
     * @param needPostInteraction Whether post-interaction is needed
     * @return offsets Encoded offsets
     */
    function buildOffsets(bool needPostInteraction) public pure returns (uint256) {
        return needPostInteraction ? 0x1 : 0x0;
    }

    /**
     * @dev Create a simple order for testing
     * @param maker Order maker
     * @param makerAsset Maker asset
     * @param takerAsset Taker asset
     * @param makingAmount Making amount
     * @param takingAmount Taking amount
     * @param needPostInteraction Whether post-interaction is needed
     * @return order Created order
     */
    function createTestOrder(
        address maker,
        address makerAsset,
        address takerAsset,
        uint256 makingAmount,
        uint256 takingAmount,
        bool needPostInteraction
    ) external view returns (IOrderMixin.Order memory) {
        return IOrderMixin.Order({
            salt: uint256(keccak256(abi.encode(block.timestamp, maker))),
            makerAsset: makerAsset,
            takerAsset: takerAsset,
            maker: maker,
            receiver: address(0),
            allowedSender: address(0),
            makingAmount: makingAmount,
            takingAmount: takingAmount,
            offsets: buildOffsets(needPostInteraction),
            interactions: ""
        });
    }
}