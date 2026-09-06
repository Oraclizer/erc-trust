// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

interface ITrustBalanceHook {
    function onTokenBalanceChanged(address from, address to) external;
}

/// @notice Single immutable token and post-balance callback for the pinned T-REX implementation.
/// @dev The zero endpoint exists only during the constructing endpoint's initial mint.
contract ERC3643HookCompliance {
    address public immutable factory;
    address public immutable token;
    address public endpoint;
    bool public bound;

    constructor(address token_) {
        require(token_ != address(0), "zero token");
        factory = msg.sender;
        token = token_;
    }

    function bindToken(address token_) external {
        require(!bound && msg.sender == token && token_ == token, "invalid binding");
        bound = true;
    }

    function unbindToken(address) external pure {
        revert("immutable binding");
    }

    function activate(address endpoint_) external {
        require(msg.sender == factory && endpoint == address(0) && endpoint_ == factory, "invalid activation");
        endpoint = endpoint_;
    }

    function canTransfer(address, address, uint256) external pure returns (bool) {
        return true;
    }

    function isTokenBound(address token_) external view returns (bool) {
        return bound && token_ == token;
    }

    function getTokenBound() external view returns (address) {
        return token;
    }

    function transferred(address from, address to, uint256) external {
        _after(from, to);
    }

    function created(address to, uint256) external {
        if (endpoint == address(0)) {
            require(msg.sender == token && bound, "only bootstrap mint");
            return;
        }
        _after(address(0), to);
    }

    function destroyed(address from, uint256) external {
        _after(from, address(0));
    }

    function _after(address from, address to) internal {
        require(msg.sender == token && bound, "only token");
        require(endpoint != address(0), "unsealed callback");
        ITrustBalanceHook(endpoint).onTokenBalanceChanged(from, to);
    }
}
