// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract NormalFlashBorrower is IERC3156FlashBorrower {
    IERC3156FlashLender public immutable vault;

    // Standard ERC-3156 callback return hash
    bytes32 private constant CALLBACK_SUCCESS = keccak256("IERC3156FlashBorrower.onFlashLoan");

    uint256 public counter = 0;

    constructor(address _vault) {
        vault = IERC3156FlashLender(_vault);
    }

    /**
     * @notice Initiates the flash loan request to the vault.
     */
    function requestFlashLoan(address token, uint256 amount) external {
        bytes memory data = ""; // optional payload passed to callback

        // 1. Call flashLoan on the vault
        vault.flashLoan(
            this, // receiver (must implement IERC3156FlashBorrower)
            token, // token address
            amount, // amount to borrow
            data
        );
    }

    /**
     * @notice The callback function invoked by UnstoppableVault during flashLoan().
     */
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        override
        returns (bytes32)
    {
        // SECURITY CHECKS:
        // 1. Ensure the caller is the trusted vault
        require(msg.sender == address(vault), "Caller must be vault");
        // 2. Ensure initiator was this contract
        require(initiator == address(this), "Untrusted loan initiator");

        // --- DO ARBITRAGE / LIQUIDATION / LOGIC HERE ---
        // At this point, this contract holds `amount` of `token`.

        counter += 1;

        // REPAYMENT APPROVAL:
        // Approve the vault to pull back the borrowed principal + fee
        IERC20(token).approve(address(vault), amount + fee);

        // Return the exact ERC-3156 magic value to signal success
        return CALLBACK_SUCCESS;
    }
}
