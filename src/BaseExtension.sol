// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "./interfaces/IOrderMixin.sol";

/**
 * @title IPreInteraction
 * @notice Interface for pre-interaction callbacks in 1inch protocol
 */
interface IPreInteraction {
    function preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external;
}

/**
 * @title IPostInteraction
 * @notice Interface for post-interaction callbacks in 1inch protocol
 */
interface IPostInteraction {
    function postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external;
}

/**
 * @title IAmountGetter
 * @notice Interface for getting order amounts
 */
interface IAmountGetter {
    function getMakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external view returns (uint256);

    function getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external view returns (uint256);
}

/**
 * @title BaseExtension
 * @notice Base contract for 1inch protocol extensions
 * @dev Provides virtual functions for pre/post interactions and amount calculations
 */
abstract contract BaseExtension is IPreInteraction, IPostInteraction, IAmountGetter {
    /**
     * @notice Pre-interaction callback (called before order execution)
     * @dev Override this function to implement custom pre-interaction logic
     */
    function preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external virtual override {
        // Call internal implementation
        _preInteraction(order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData);
    }

    /**
     * @notice Post-interaction callback (called after order execution)
     * @dev Override this function to implement custom post-interaction logic
     */
    function postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external virtual override {
        // Call internal implementation
        _postInteraction(order, extension, orderHash, taker, makingAmount, takingAmount, remainingMakingAmount, extraData);
    }

    /**
     * @notice Get making amount for dynamic orders
     * @dev Override this function to implement custom amount calculations
     */
    function getMakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external view virtual override returns (uint256) {
        return _getMakingAmount(order, extension, orderHash, taker, takingAmount, remainingMakingAmount, extraData);
    }

    /**
     * @notice Get taking amount for dynamic orders
     * @dev Override this function to implement custom amount calculations
     */
    function getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) external view virtual override returns (uint256) {
        return _getTakingAmount(order, extension, orderHash, taker, makingAmount, remainingMakingAmount, extraData);
    }

    /**
     * @notice Internal pre-interaction implementation
     * @dev Override in derived contracts
     */
    function _preInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal virtual {
        // Default implementation: no-op
    }

    /**
     * @notice Internal post-interaction implementation
     * @dev Override in derived contracts
     */
    function _postInteraction(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal virtual {
        // Default implementation: no-op
    }

    /**
     * @notice Internal get making amount implementation
     * @dev Override in derived contracts for dynamic pricing
     */
    function _getMakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 takingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view virtual returns (uint256) {
        // Default implementation: return static amount
        return order.makingAmount;
    }

    /**
     * @notice Internal get taking amount implementation
     * @dev Override in derived contracts for dynamic pricing
     */
    function _getTakingAmount(
        IOrderMixin.Order calldata order,
        bytes calldata extension,
        bytes32 orderHash,
        address taker,
        uint256 makingAmount,
        uint256 remainingMakingAmount,
        bytes calldata extraData
    ) internal view virtual returns (uint256) {
        // Default implementation: return static amount
        return order.takingAmount;
    }
}