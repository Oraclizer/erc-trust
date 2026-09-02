// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

/// @notice Test-only ERC-3643-shaped token with an explicit one-agent topology extension and switchable
///         upstream failure modes.
/// @dev This is a clean-room conformance fixture, not an ERC-3643 implementation. Its forced transfer
///      does not unfreeze automatically, so the adapter's frozen-amount resynchronisation is exercised
///      explicitly; the second fixture (MockERC3643TokenTrex) unfreezes the way ERC-3643 does.
contract MockERC3643Token {
    enum Mode {
        NORMAL,
        TRANSFER_RETURNS_FALSE,
        TRANSFER_NO_EFFECT,
        FREEZE_NO_EFFECT,
        RESTRICT_NO_EFFECT,
        FROZEN_VIEW_REVERTS,
        FROZEN_VIEW_LONG
    }

    address public owner;
    address public identityRegistry;
    address public compliance;
    address public exclusiveAgent;
    Mode public mode;
    bool public paused;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) internal _frozenTokens;
    mapping(address => bool) public isFrozen;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event TokensFrozen(address indexed account, uint256 amount);
    event TokensUnfrozen(address indexed account, uint256 amount);
    event AddressFrozen(address indexed account, bool frozen);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "owner");
        _;
    }

    modifier onlyAgent() {
        require(msg.sender == exclusiveAgent && exclusiveAgent != address(0), "agent");
        _;
    }

    constructor(address identityRegistry_, address compliance_, uint256 supply) {
        owner = msg.sender;
        identityRegistry = identityRegistry_;
        compliance = compliance_;
        balanceOf[msg.sender] = supply;
        emit Transfer(address(0), msg.sender, supply);
    }

    /// @dev Test-only failure switch; any account may flip it because the fixture models the upstream
    ///      token misbehaving, not an authorization surface.
    function setMode(Mode mode_) external {
        mode = mode_;
    }

    /// @dev Test-only seeding of legacy state before the seal; only usable while no Agent exists. The
    ///      balance is moved from the owner so that the supply stays accounted.
    function seedLegacyState(address account, uint256 balance, uint256 frozenAmount, bool restricted)
        external
        onlyOwner
    {
        require(exclusiveAgent == address(0), "sealed agent");
        require(frozenAmount <= balance && balanceOf[msg.sender] >= balance, "free balance");
        balanceOf[msg.sender] -= balance;
        balanceOf[account] += balance;
        emit Transfer(msg.sender, account, balance);
        _frozenTokens[account] = frozenAmount;
        isFrozen[account] = restricted;
    }

    function getFrozenTokens(address account) external view returns (uint256) {
        if (mode == Mode.FROZEN_VIEW_REVERTS) revert("frozen view unavailable");
        if (mode == Mode.FROZEN_VIEW_LONG) {
            uint256 frozen = _frozenTokens[account];
            assembly ("memory-safe") {
                mstore(0, frozen)
                mstore(32, 1)
                return(0, 64)
            }
        }
        return _frozenTokens[account];
    }

    function isAgent(address account) external view returns (bool) {
        return account == exclusiveAgent && account != address(0);
    }

    // ------------------------------------------------------------------
    // Owner surface (inert once the governor owns the token)
    // ------------------------------------------------------------------

    function setExclusiveAgent(address agent) external onlyOwner {
        require(exclusiveAgent == address(0) && agent != address(0), "sealed agent");
        exclusiveAgent = agent;
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        require(nextOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, nextOwner);
        owner = nextOwner;
    }

    function setIdentityRegistry(address registry) external onlyOwner {
        identityRegistry = registry;
    }

    function setCompliance(address compliance_) external onlyOwner {
        compliance = compliance_;
    }

    // ------------------------------------------------------------------
    // Agent surface
    // ------------------------------------------------------------------

    function forcedTransfer(address from, address to, uint256 amount) external onlyAgent returns (bool) {
        require(from != address(0) && to != address(0), "zero");
        require(balanceOf[from] >= amount, "balance");
        if (mode == Mode.TRANSFER_RETURNS_FALSE) return false;
        if (mode == Mode.TRANSFER_NO_EFFECT) return true;
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
        return true;
    }

    function batchForcedTransfer(address[] calldata from, address[] calldata to, uint256[] calldata amounts)
        external
        onlyAgent
    {
        require(from.length == to.length && to.length == amounts.length, "length");
        for (uint256 i; i < from.length; ++i) {
            require(balanceOf[from[i]] >= amounts[i], "balance");
            unchecked {
                balanceOf[from[i]] -= amounts[i];
                balanceOf[to[i]] += amounts[i];
            }
            emit Transfer(from[i], to[i], amounts[i]);
        }
    }

    function freezePartialTokens(address account, uint256 amount) external onlyAgent {
        require(balanceOf[account] - _frozenTokens[account] >= amount, "free balance");
        if (mode == Mode.FREEZE_NO_EFFECT) return;
        _frozenTokens[account] += amount;
        emit TokensFrozen(account, amount);
    }

    function unfreezePartialTokens(address account, uint256 amount) external onlyAgent {
        require(_frozenTokens[account] >= amount, "frozen balance");
        if (mode == Mode.FREEZE_NO_EFFECT) return;
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
        if (mode == Mode.RESTRICT_NO_EFFECT) return;
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

    function mint(address to, uint256 amount) external onlyAgent {
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external onlyAgent {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        emit Transfer(from, address(0), amount);
    }

    function recoveryAddress(address lostWallet, address newWallet, address) external onlyAgent returns (bool) {
        uint256 amount = balanceOf[lostWallet];
        balanceOf[lostWallet] = 0;
        balanceOf[newWallet] += amount;
        emit Transfer(lostWallet, newWallet, amount);
        return true;
    }

    function pause() external onlyAgent {
        paused = true;
    }

    function unpause() external onlyAgent {
        paused = false;
    }
}
