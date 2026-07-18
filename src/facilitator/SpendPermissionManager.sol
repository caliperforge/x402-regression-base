// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title SpendPermissionManager  -  session-key delegation-cap primitive (Base substrate)
/// @notice A session-key style spend-permission primitive matching the shape
/// of Coinbase's `SpendPermissionManager` on Base. Not a vendored copy;
/// the fields (account, spender, token, allowance, period, start, end,
/// salt) mirror the live manager's `SpendPermission` struct so a
/// downstream integrator can wire our planted twin against their own
/// manager's fork.
///
/// Enforces the delegation-cap invariant referenced by V06:
///
///     spentInPeriod[digest][periodIndex] + amount <= allowance
///
/// checked-and-persisted atomically before the token transfer. The clean
/// manager below implements the invariant; the planted variant in
/// `test/planted/V06_DelegationCap.planted.t.sol` removes the counter
/// update and lets a spender move balance past the cap up to the token
/// allowance across unbounded calls in one period.
///
/// HARD-rail: this is a class-level twin against a synthesized minimal
/// manager. No specific-instance disclosure against Coinbase's live
/// `SpendPermissionManager` is claimed; that manager enforces the
/// invariant correctly.
contract SpendPermissionManager {
    struct SpendPermission {
        address account;
        address spender;
        address token;
        uint256 allowance;
        uint256 period;
        uint256 start;
        uint256 end;
        uint256 salt;
    }

    mapping(bytes32 => mapping(uint256 => uint256)) public spentInPeriod;

    event Spent(
        bytes32 indexed digestKey,
        address indexed spender,
        uint256 indexed periodIndex,
        uint256 amount
    );

    function digest(SpendPermission memory p) public pure returns (bytes32) {
        bytes32 h = keccak256(
            abi.encode(
                p.account, p.spender, p.token, p.allowance, p.period, p.start, p.end, p.salt
            )
        );
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function currentPeriodIndex(SpendPermission memory p) public view returns (uint256) {
        return (block.timestamp - p.start) / p.period;
    }

    function spend(SpendPermission calldata p, uint8 v, bytes32 r, bytes32 s, uint256 amount)
        external
    {
        require(msg.sender == p.spender, "SPM: not spender");
        require(block.timestamp >= p.start && block.timestamp <= p.end, "SPM: window");
        require(amount > 0 && amount <= p.allowance, "SPM: amount");

        bytes32 d = digest(p);
        address signer = ecrecover(d, v, r, s);
        require(signer == p.account && signer != address(0), "SPM: bad sig");

        uint256 periodIndex = currentPeriodIndex(p);

        // V06 defense: cumulative counter enforced and persisted BEFORE the
        // external token call. The planted variant removes this block.
        uint256 already = spentInPeriod[d][periodIndex];
        require(already + amount <= p.allowance, "SPM: cap");
        spentInPeriod[d][periodIndex] = already + amount;

        require(
            IERC20Minimal(p.token).transferFrom(p.account, p.spender, amount), "SPM: transfer"
        );
        emit Spent(d, p.spender, periodIndex, amount);
    }
}
