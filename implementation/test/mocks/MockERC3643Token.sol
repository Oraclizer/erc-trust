// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;

/// @notice Test-only ERC-3643-shaped token with an explicit one-agent topology extension.
/// @dev This is a clean-room conformance fixture, not an ERC-3643 implementation.
contract MockERC3643Token {
    address public owner;
    address public immutable identityRegistry;
    address public immutable compliance;
    address public exclusiveAgent;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public getFrozenTokens;
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

    function isAgent(address account) external view returns (bool) {
        return account == exclusiveAgent && account != address(0);
    }

    function setExclusiveAgent(address agent) external onlyOwner {
        require(exclusiveAgent == address(0) && agent != address(0), "sealed agent");
        exclusiveAgent = agent;
    }

    function transferOwnership(address nextOwner) external onlyOwner {
        require(nextOwner != address(0), "zero owner");
        emit OwnershipTransferred(owner, nextOwner);
        owner = nextOwner;
    }

    function forcedTransfer(address from, address to, uint256 amount) external onlyAgent returns (bool) {
        require(from != address(0) && to != address(0), "zero");
        require(balanceOf[from] >= amount, "balance");
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
        require(balanceOf[account] - getFrozenTokens[account] >= amount, "free balance");
        getFrozenTokens[account] += amount;
        emit TokensFrozen(account, amount);
    }

    function unfreezePartialTokens(address account, uint256 amount) external onlyAgent {
        require(getFrozenTokens[account] >= amount, "frozen balance");
        getFrozenTokens[account] -= amount;
        emit TokensUnfrozen(account, amount);
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
}
