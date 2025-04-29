// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/// @title AsciiChainNFTx
/// @dev ERC721 whose “image” is raw ASCII stored on-chain, plus a getter
contract AsciiChainNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    uint256 public mintPrice;
    uint256 public maxSupply;

    // who’s allowed to mint
    mapping(address => bool) public minters;

    // store each token’s ASCII art
    mapping(uint256 => string) private _asciiArt;

    modifier onlyMinter() {
        require(minters[msg.sender], "Not authorized");
        _;
    }

    /// @param name_    NFT name
    /// @param symbol_  NFT symbol
    /// @param price_   mint price in wei
    /// @param supply_  total possible tokens
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 price_,
        uint256 supply_
    ) ERC721(name_, symbol_) {
        mintPrice = price_;
        maxSupply = supply_;
        // owner starts out as an authorized minter
        minters[msg.sender] = true;
    }

    /// @notice Mint a new ASCII NFT
    /// @param to    recipient address
    /// @param art   the ASCII string you want stored
    function safeMint(address to, string memory art)
        external
        payable
        onlyMinter
    {
        uint256 id = _tokenIdCounter.current();
        require(id < maxSupply, "Exceeds max supply");
        require(msg.value >= mintPrice, "Insufficient ETH");

        _tokenIdCounter.increment();
        _safeMint(to, id);
        _asciiArt[id] = art;
    }

    /// @notice Grant or revoke mint rights
    function setMinter(address who, bool allowed) external onlyOwner {
        minters[who] = allowed;
    }

    /// @notice Withdraw all ETH from contract
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /// @notice Read back the raw ASCII art for a given token
    function getArt(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        return _asciiArt[tokenId];
    }

    /// @notice Expose on-chain “performance” data
    /// @dev Note: contracts can only see block/tx metadata, not full chain size or real throughput
    function getChainMetrics()
        external
        view
        returns (
            uint256 blockNumber,
            uint256 timestamp,
            uint256 gaslimit,
            uint256 baseFee,
            uint256 gasPrice,
            uint256 chainId
        )
    {
        blockNumber = block.number;       // current height
        timestamp   = block.timestamp;    // block timestamp
        gaslimit    = block.gaslimit;     // max gas this block allows
        baseFee     = block.basefee;      // current EIP-1559 base fee
        gasPrice    = tx.gasprice;        // what this tx paid per gas
        chainId     = block.chainid;      // network ID
    }

    // allow the contract to receive ETH
    receive() external payable {}
    fallback() external payable {}
}
