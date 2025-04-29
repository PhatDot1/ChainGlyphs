// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title AsciiChainNFTWithParams
/// @notice Two-phase mint: first emit on-chain metrics, then finalize with both on-chain + off-chain stats plus a custom time field
contract AsciiChainNFTWithParams is ERC721, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct Metrics {
        uint256 time;           // custom time field (e.g. duration of phase1)
        uint256 gaslimit;
        uint256 baseFee;
        uint256 gasPrice;
        uint256 priorityFee;
        uint256 chainId;
        uint256 diskSize;       // off-chain: total chain disk size
        uint256 txThroughput;   // off-chain: tx/s
        uint256 archiveSize;    // off-chain: archive DB size
    }

    Counters.Counter private _tokenIdCounter;
    uint256 public mintPrice;
    uint256 public maxSupply;

    mapping(address => bool)       public minters;
    mapping(uint256 => string)     private _asciiArt;
    mapping(uint256 => Metrics)    private _metrics;

    /// @notice emitted in Phase 1
    event ChainMetrics(
        uint256 gaslimit,
        uint256 baseFee,
        uint256 gasPrice,
        uint256 chainId,
        address indexed caller
    );

    modifier onlyMinter() {
        require(minters[msg.sender], "Not authorized");
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 price_,
        uint256 supply_
    ) ERC721(name_, symbol_) {
        mintPrice = price_;
        maxSupply  = supply_;
        minters[msg.sender] = true;
    }

    /// @notice Phase 1: mint stub + emit on-chain metrics
    function safeMintWithMetrics(address to, string memory art)
        external payable onlyMinter
    {
        uint256 id = _tokenIdCounter.current();
        require(id < maxSupply, "Exceeds max supply");
        require(msg.value >= mintPrice, "Insufficient ETH");

        emit ChainMetrics(
            block.gaslimit,
            block.basefee,
            tx.gasprice,
            block.chainid,
            msg.sender
        );

        _tokenIdCounter.increment();
        _safeMint(to, id);
        _asciiArt[id] = art;
    }

    /// @notice Phase 2: finalize mint with full metrics + off-chain stats + custom time
    function safeMintWithParams(
        address to,
        string memory art,
        uint256 time,
        uint256 gaslimit,
        uint256 baseFee,
        uint256 gasPrice,
        uint256 priorityFee,
        uint256 chainId,
        uint256 diskSize,
        uint256 txThroughput,
        uint256 archiveSize
    ) external payable onlyMinter {
        uint256 id = _tokenIdCounter.current();
        require(id < maxSupply, "Exceeds max supply");
        require(msg.value >= mintPrice, "Insufficient ETH");

        _metrics[id] = Metrics({
            time:           time,
            gaslimit:       gaslimit,
            baseFee:        baseFee,
            gasPrice:       gasPrice,
            priorityFee:    priorityFee,
            chainId:        chainId,
            diskSize:       diskSize,
            txThroughput:   txThroughput,
            archiveSize:    archiveSize
        });

        _tokenIdCounter.increment();
        _safeMint(to, id);
        _asciiArt[id] = art;
    }

    function setMinter(address who, bool allowed) external onlyOwner {
        minters[who] = allowed;
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function getArt(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        return _asciiArt[tokenId];
    }

    function getMetrics(uint256 tokenId) external view returns (Metrics memory) {
        require(_exists(tokenId), "Nonexistent token");
        return _metrics[tokenId];
    }

    /// @notice Build on-chain SVG + JSON metadata with all metrics & stats
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Nonexistent token");
        Metrics memory m = _metrics[tokenId];
        string memory art = _asciiArt[tokenId];

        // 1) SVG
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600">',
                  '<style>text{white-space:pre;font-family:monospace;font-size:12px;fill:#000}</style>',
                  '<rect width="100%" height="100%" fill="#fff"/>',
                  '<text x="10" y="20" xml:space="preserve">',
                    art,
                  '</text></svg>'
            )
        );
        string memory imageURI = string(
            abi.encodePacked(
              "data:image/svg+xml;base64,",
              Base64.encode(bytes(svg))
            )
        );

        // 2) JSON metadata
        bytes memory json = abi.encodePacked(
          '{"name":"', name(), ' #', tokenId.toString(),
          '","description":"ASCII art + on-chain & off-chain metrics + custom time",',
          '"image":"', imageURI, '","attributes":[',
            '{"trait_type":"time","value":',           m.time.toString(),           '},',
            '{"trait_type":"gaslimit","value":',       m.gaslimit.toString(),       '},',
            '{"trait_type":"gasPrice","value":',       m.gasPrice.toString(),       '},',
            '{"trait_type":"priorityFee","value":',    m.priorityFee.toString(),    '},',
            '{"trait_type":"txThroughput","value":',   m.txThroughput.toString(),   '}',
          ']}'
        );

        return string(
          abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(json)
          )
        );
    }

    receive() external payable {}
    fallback() external payable {}
}
