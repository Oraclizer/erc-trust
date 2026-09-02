// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

import {IERC3643IdentityRegistry, IERC3643Compliance} from "../../src/interfaces/IERC3643External.sol";

/// @notice Independent second conformance fixture written from the ERC-3643 interface semantics: forced
///         transfers unfreeze automatically, ordinary transfers respect address and partial freezes, and
///         the owner keeps the full ERC-3643 administration surface (agents, registries, pause,
///         recovery, supply) until the exclusive Agent extension is set.
/// @dev Clean-room fixture written from the public interface description; it is not derived from any
///      ERC-3643 implementation source and is not an ERC-3643 implementation.
contract MockERC3643TokenTrex {
    address public owner;
    address public identityRegistry;
    address public compliance;
    address public exclusiveAgent;
    bool public paused;
    uint256 public totalSupply;

    mapping(address => bool) internal _agents;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) internal _frozenTokens;
    mapping(address => bool) public isFrozen;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TokensFrozen(address indexed account, uint256 amount);
    event TokensUnfrozen(address indexed account, uint256 amount);
    event AddressFrozen(address indexed account, bool frozen);
    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RecoverySuccess(address indexed lostWallet, address indexed newWallet, address indexed investorOnchainID);

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    modifier onlyAgent() {
        require(isAgent(msg.sender), "agent");
        _;
    }

    constructor(address identityRegistry_, address compliance_, uint256 supply) {
        owner = msg.sender;
        identityRegistry = identityRegistry_;
        compliance = compliance_;
        _agents[msg.sender] = true;
        emit AgentAdded(msg.sender);
        totalSupply = supply;
        balanceOf[msg.sender] = supply;
        emit Transfer(address(0), msg.sender, supply);
    }

    function getFrozenTokens(address account) external view returns (uint256) {
        return _frozenTokens[account];
    }

    /// @dev Once the exclusive Agent is set, it is the only Agent; the historical agent list is inert.
    function isAgent(address account) public view returns (bool) {
        if (exclusiveAgent != address(0)) return account == exclusiveAgent;
        return _agents[account];
    }

    // ------------------------------------------------------------------
    // Ordinary transfers
    // ------------------------------------------------------------------

    function transfer(address to, uint256 amount) external returns (bool) {
        require(!paused, "paused");
        require(!isFrozen[msg.sender] && !isFrozen[to], "address frozen");
        require(amount <= balanceOf[msg.sender] - _frozenTokens[msg.sender], "frozen tokens");
        require(IERC3643IdentityRegistry(identityRegistry).isVerified(to), "unverified");
        require(IERC3643Compliance(compliance).canTransfer(msg.sender, to, amount), "compliance");
        _move(msg.sender, to, amount);
        return true;
    }

    // ------------------------------------------------------------------
    // Owner surface
    // ------------------------------------------------------------------

    function addAgent(address agent) external onlyOwner {
        require(exclusiveAgent == address(0), "exclusive agent");
        _agents[agent] = true;
        emit AgentAdded(agent);
    }

    function removeAgent(address agent) external onlyOwner {
        require(exclusiveAgent == address(0), "exclusive agent");
        _agents[agent] = false;
        emit AgentRemoved(agent);
    }

    function setExclusiveAgent(address agent) external onlyOwner {
        require(exclusiveAgent == address(0) && agent != address(0), "sealed agent");
        exclusiveAgent = agent;
    }

    function setIdentityRegistry(address registry) external onlyOwner {
        identityRegistry = registry;
    }

    function setCompliance(address compliance_) external onlyOwner {
        compliance = compliance_;
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        require(nextOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, nextOwner);
        owner = nextOwner;
    }

    // ------------------------------------------------------------------
    // Agent surface
    // ------------------------------------------------------------------

    function forcedTransfer(address from, address to, uint256 amount) external onlyAgent returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        uint256 free = balanceOf[from] - _frozenTokens[from];
        if (amount > free) {
            uint256 unfreeze = amount - free;
            _frozenTokens[from] -= unfreeze;
            emit TokensUnfrozen(from, unfreeze);
        }
        require(IERC3643IdentityRegistry(identityRegistry).isVerified(to), "unverified");
        _move(from, to, amount);
        return true;
    }

    function batchForcedTransfer(address[] calldata from, address[] calldata to, uint256[] calldata amounts)
        external
        onlyAgent
    {
        require(from.length == to.length && to.length == amounts.length, "length");
        for (uint256 i; i < from.length; ++i) {
            require(balanceOf[from[i]] >= amounts[i], "balance");
            uint256 free = balanceOf[from[i]] - _frozenTokens[from[i]];
            if (amounts[i] > free) {
                _frozenTokens[from[i]] -= amounts[i] - free;
                emit TokensUnfrozen(from[i], amounts[i] - free);
            }
            _move(from[i], to[i], amounts[i]);
        }
    }

    function mint(address to, uint256 amount) external onlyAgent {
        require(IERC3643IdentityRegistry(identityRegistry).isVerified(to), "unverified");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyAgent {
        require(balanceOf[from] >= amount, "balance");
        uint256 free = balanceOf[from] - _frozenTokens[from];
        if (amount > free) {
            _frozenTokens[from] -= amount - free;
            emit TokensUnfrozen(from, amount - free);
        }
        totalSupply -= amount;
        balanceOf[from] -= amount;
        emit Transfer(from, address(0), amount);
    }

    function recoveryAddress(address lostWallet, address newWallet, address investorOnchainID)
        external
        onlyAgent
        returns (bool)
    {
        uint256 amount = balanceOf[lostWallet];
        uint256 frozen = _frozenTokens[lostWallet];
        _frozenTokens[lostWallet] = 0;
        _frozenTokens[newWallet] += frozen;
        isFrozen[newWallet] = isFrozen[lostWallet];
        isFrozen[lostWallet] = false;
        _move(lostWallet, newWallet, amount);
        emit RecoverySuccess(lostWallet, newWallet, investorOnchainID);
        return true;
    }

    function freezePartialTokens(address account, uint256 amount) external onlyAgent {
        require(balanceOf[account] - _frozenTokens[account] >= amount, "free balance");
        _frozenTokens[account] += amount;
        emit TokensFrozen(account, amount);
    }

    function unfreezePartialTokens(address account, uint256 amount) external onlyAgent {
        require(_frozenTokens[account] >= amount, "frozen balance");
        _frozenTokens[account] -= amount;
        emit TokensUnfrozen(account, amount);
    }

    function batchFreezePartialTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyAgent {
        require(accounts.length == amounts.length, "length");
        for (uint256 i; i < accounts.length; ++i) {
            require(balanceOf[accounts[i]] - _frozenTokens[accounts[i]] >= amounts[i], "free balance");
            _frozenTokens[accounts[i]] += amounts[i];
            emit TokensFrozen(accounts[i], amounts[i]);
        }
    }

    function batchUnfreezePartialTokens(address[] calldata accounts, uint256[] calldata amounts) external onlyAgent {
        require(accounts.length == amounts.length, "length");
        for (uint256 i; i < accounts.length; ++i) {
            require(_frozenTokens[accounts[i]] >= amounts[i], "frozen balance");
            _frozenTokens[accounts[i]] -= amounts[i];
            emit TokensUnfrozen(accounts[i], amounts[i]);
        }
    }

    function setAddressFrozen(address account, bool frozen) external onlyAgent {
        isFrozen[account] = frozen;
        emit AddressFrozen(account, frozen);
    }

    function batchSetAddressFrozen(address[] calldata accounts, bool[] calldata values) external onlyAgent {
        require(accounts.length == values.length, "length");
        for (uint256 i; i < accounts.length; ++i) {
            isFrozen[accounts[i]] = values[i];
            emit AddressFrozen(accounts[i], values[i]);
        }
    }

    function pause() external onlyAgent {
        paused = true;
    }

    function unpause() external onlyAgent {
        paused = false;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(from != address(0) && to != address(0), "zero");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
