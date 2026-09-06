// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;
import {ERC3643HookCompliance} from "./ERC3643HookCompliance.sol";
import {ERC3643HookGovernor} from "./ERC3643HookGovernor.sol";

interface ITrexBootstrap {
    function init(
        address registry,
        address compliance,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address onchainID
    ) external;
    function addAgent(address agent) external;
    function mint(address holder, uint256 amount) external;
    function unpause() external;
    function transferOwnership(address owner) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address holder) external view returns (uint256);
    function getFrozenTokens(address holder) external view returns (uint256);
    function isFrozen(address holder) external view returns (bool);
}

/// @notice Fixed membership identity policy, including the endpoint as the custody address.
contract ERC3643HookIdentityRegistry {
    mapping(address => bool) private _verified;

    constructor(address holder, address[] memory eligible) {
        require(holder != address(0), "zero holder");
        _verified[holder] = true;
        _verified[msg.sender] = true;
        for (uint256 i; i < eligible.length; ++i) {
            require(eligible[i] != address(0), "zero identity");
            _verified[eligible[i]] = true;
        }
    }

    function isVerified(address account) external view returns (bool) {
        return _verified[account];
    }
}

/// @dev Internal constructor code, executed as the new endpoint itself. No caller-supplied
///      bootstrap contract, governor, registry, hook, existing token, or Agent list is accepted.
library ERC3643HookDeployment {
    bytes32 internal constant TOKEN_CREATION_HASH = 0x1278126a159c0439e8defb9b59f26ae2ad6790cb0c99d81a0722a0bb23ab9438;

    function prepare(address tokenCreationSource, address holder, uint256 supply, address[] memory eligible)
        internal
        returns (address)
    {
        bytes memory tokenCreationCode = tokenCreationSource.code;
        require(keccak256(tokenCreationCode) == TOKEN_CREATION_HASH, "unapproved token creation code");
        address token;
        assembly { token := create(0, add(tokenCreationCode, 32), mload(tokenCreationCode)) }
        require(token != address(0), "token creation failed");
        ERC3643HookIdentityRegistry registry = new ERC3643HookIdentityRegistry(holder, eligible);
        ERC3643HookCompliance hook = new ERC3643HookCompliance(token);
        ITrexBootstrap upstream = ITrexBootstrap(token);
        upstream.init(address(registry), address(hook), "TRUST T-REX", "TRX", 18, address(0));
        // The stock token starts with no Agent. This single addition is the final Agent set.
        upstream.addAgent(address(this));
        if (supply != 0) upstream.mint(holder, supply);
        require(
            upstream.totalSupply() == supply && upstream.balanceOf(holder) == supply
                && upstream.getFrozenTokens(holder) == 0 && !upstream.isFrozen(holder),
            "initial state mismatch"
        );
        ERC3643HookGovernor governor = new ERC3643HookGovernor(token, address(registry), address(hook), token.codehash);
        hook.activate(address(this));
        upstream.unpause();
        upstream.transferOwnership(address(governor));
        return address(governor);
    }
}
