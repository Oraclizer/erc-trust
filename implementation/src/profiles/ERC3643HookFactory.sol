// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.36;
import {TrustKernelTypes} from "../generated/IERCTrustKernel.sol";

interface IHookAdapterProfile {
    function trustProfile() external view returns (TrustKernelTypes.ProfileDescriptor memory);
    function token() external view returns (address);
    function profileGovernor() external view returns (address);
}

/// @notice Stateless factory for exact fresh-unit creation code.
/// @dev The endpoint constructor owns initialization and the seal. Creation code is supplied
///      as calldata and hash-checked to avoid embedding it in an oversized factory runtime.
contract ERC3643HookFactory {
    bytes32 public constant ADAPTER_CREATION_HASH = 0x7e196e99993b30b186c3a1cbeb24e89d926dbd990941fc83b3269a0d39b147b2;
    address public immutable tokenCreationSource;

    constructor(bytes memory tokenCreationCode) {
        require(
            keccak256(tokenCreationCode) == 0x1278126a159c0439e8defb9b59f26ae2ad6790cb0c99d81a0722a0bb23ab9438,
            "unapproved token creation code"
        );
        tokenCreationSource = address(new ERC3643CreationCode(tokenCreationCode));
    }
    event HookUnitCreated(address indexed token, address indexed adapter, address indexed governor);

    function deploy(
        bytes memory adapterCreationCode,
        address authority,
        bytes32 authorityRef,
        address initialHolder,
        uint256 supply,
        address[] memory eligible
    ) external returns (address token, address adapter, address governor) {
        require(keccak256(adapterCreationCode) == ADAPTER_CREATION_HASH, "unapproved adapter creation code");
        bytes memory creation = abi.encodePacked(
            adapterCreationCode,
            abi.encode(tokenCreationSource, authority, authorityRef, initialHolder, supply, eligible)
        );
        require(creation.length <= 49152, "initcode limit");
        assembly { adapter := create(0, add(creation, 32), mload(creation)) }
        require(adapter != address(0), "unit creation failed");
        IHookAdapterProfile endpoint = IHookAdapterProfile(adapter);
        require(endpoint.trustProfile().full, "unit not sealed");
        token = endpoint.token();
        governor = endpoint.profileGovernor();
        emit HookUnitCreated(token, adapter, governor);
    }
}

/// @dev Bytecode carrier only; the endpoint hashes its code before using it as token initcode.
contract ERC3643CreationCode {
    constructor(bytes memory creationCode) {
        assembly { return(add(creationCode, 32), mload(creationCode)) }
    }
}
