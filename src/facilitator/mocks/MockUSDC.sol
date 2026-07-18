// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/// @title MockUSDC  -  test-only USDC-shape token for the Base x402 planted-twin harness
/// @notice Not production-safe. On Base mainnet the harness targets Circle's
/// canonical USDC at `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`; on
/// Sepolia the harness targets Circle's Sepolia USDC test token if
/// available, else this contract deployed same-run. See spec §2.2 stage 1.
///
/// The facilitator's settle() uses the standard ERC-20 `transferFrom` path
/// (payer pre-approves the facilitator; the payer's authorization signature
/// is verified against the facilitator's own EIP-712 domain, NOT against
/// the token's EIP-3009 domain). Struct field naming in
/// `IX402Facilitator.PaymentAuthorization` matches EIP-3009 verbatim so
/// M2 can swap in a full EIP-3009 layer without breaking downstream users.
/// M1 keeps the harness at facilitator-domain invariants only.
contract MockUSDC {
    string public constant name = "USD Coin";
    string public constant symbol = "USDC";
    uint8 public constant decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// @notice test-only mint. Not a canonical USDC entry point.
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "USDC: allowance");
        require(balanceOf[from] >= amount, "USDC: balance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
