// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IERC6551Registry.sol";
import "./ERC6551AccountUpgradeable.sol";

/// @notice ERC-6551 Registry using CREATE + RLP‐nonce prediction.
///   - cloneCount tracks how many clones have been made.
///   - predictNextClone() returns the address for the *next* CREATE.
///   - createAccount() does a Clones.clone (which uses CREATE) and initializes.
contract ERC6551RegistryWithPredict is IERC6551Registry {
    using Clones for address;

    /// @notice Implementation behind all clones
    address public immutable accountImplementation;

    /// @dev How many clones we’ve done so far.
    uint256 public cloneCount;

    /// @dev Map key=(chainId,tokenContract,tokenId,salt) → cloned address
    mapping(bytes32 => address) public accounts;

    constructor(address _implementation) {
        require(_implementation != address(0), "Zero impl");
        accountImplementation = _implementation;
    }

    /// @inheritdoc IERC6551Registry
    function createAccount(
        address,          // ignored; we only use accountImplementation
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external override returns (address account) {
        // derive a unique key
        bytes32 key = keccak256(abi.encodePacked(chainId, tokenContract, tokenId, salt));

        // if we haven’t made it yet, do so
        account = accounts[key];
        if (account == address(0)) {
            // bump our internal clone‐nonce
            cloneCount++;

            // predict where CREATE will place the next contract:
            account = _predict(address(this), cloneCount);

            // actually deploy the minimal‐proxy via CREATE:
            address clone = accountImplementation.clone();
            require(clone == account, "Clone at unexpected addr");

            // initialize and store
            ERC6551AccountUpgradeable(clone).initialize(
                address(this),
                accountImplementation,
                chainId,
                tokenContract,
                tokenId
            );
            accounts[key] = clone;

            emit ERC6551AccountCreated(
                clone,
                accountImplementation,
                salt,
                chainId,
                tokenContract,
                tokenId
            );
        }
    }

    /// @inheritdoc IERC6551Registry
    function account(
        address, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId
    ) external view override returns (address) {
        bytes32 key = keccak256(abi.encodePacked(chainId, tokenContract, tokenId, salt));
        return accounts[key];
    }

    /// @notice Returns the address the *next* CREATE() will use.
    function predictNextClone() external view returns (address) {
        return _predict(address(this), cloneCount + 1);
    }

    /// @dev RLP‐encode [factory, nonce] for nonce<128: 0xd6 0x94 {20b factory} {1b nonce}
    function _predict(address factory, uint256 nonce) internal pure returns (address) {
        bytes memory data = abi.encodePacked(
            // RLP list prefix for 22 bytes of payload (0xc0 + 22 = 0xd6)
            hex"d6",
            // RLP string prefix for 20‐byte address (0x80 + 20 = 0x94)
            hex"94",
            factory,
            // single‐byte nonce (must be <128 for this to work)
            bytes1(uint8(nonce))
        );
        // keccak256 of that -> 32 bytes -> last 20 bytes = address
        bytes32 hash = keccak256(data);
        return address(uint160(uint(hash)));
    }
}
