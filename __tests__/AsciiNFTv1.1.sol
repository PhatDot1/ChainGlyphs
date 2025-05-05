// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @title AsciiChainEvalNFT
/// @notice Two-phase mint: Phase 1 emits on-chain metrics; Phase 2 finalizes mint and
/// on-chain tokenURI builds both metadata **and** a procedurally generated ASCII visual
contract AsciiChainEvalNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct Metrics {
        uint256 time;           // custom “duration” from your script
        uint256 gaslimit;
        uint256 baseFee;
        uint256 gasPrice;
        uint256 priorityFee;
        uint256 chainId;
        uint256 diskSize;       // off-chain, if you want
        uint256 txThroughput;   // off-chain sample
        uint256 archiveSize;    // off-chain, if you want
    }

    Counters.Counter private _tokenIdCounter;
    uint256 public mintPrice;
    uint256 public maxSupply;
    mapping(address => bool) public minters;
    mapping(uint256 => Metrics) private _metrics;

    /// @notice emits your on-chain snapshot in Phase 1
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
        maxSupply = supply_;
        minters[msg.sender] = true;
    }

    /// @notice Phase 1: emit on-chain metrics, mint a stub token
    function safeMintWithMetrics(address to)
        external
        payable
        onlyMinter
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
    }

    /// @notice Phase 2: finalize with BOTH on-chain + off-chain stats + custom time
    function safeMintWithParams(
        address to,
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
            time: time,
            gaslimit: gaslimit,
            baseFee: baseFee,
            gasPrice: gasPrice,
            priorityFee: priorityFee,
            chainId: chainId,
            diskSize: diskSize,
            txThroughput: txThroughput,
            archiveSize: archiveSize
        });

        _tokenIdCounter.increment();
        _safeMint(to, id);
    }

    function setMinter(address who, bool allowed) external onlyOwner {
        minters[who] = allowed;
    }
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /// @notice View stored metrics
    function getMetrics(uint256 tokenId) external view returns (Metrics memory) {
        require(_exists(tokenId), "Nonexistent token");
        return _metrics[tokenId];
    }

    /// @notice Build on-chain SVG + metadata JSON (Base64-encoded)
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "Nonexistent token");
        Metrics memory m = _metrics[tokenId];

        //
        // 1) BUILD NAME = JUST THE BAR STRING
        //
        uint256 bars = m.gaslimit / 12_000_000;
        if (bars < 1) bars = 1;
        if (bars > 50) bars = 50;
        string memory barStr;
        for (uint256 i = 0; i < bars; i++) {
            barStr = string(abi.encodePacked(barStr, "|"));
        }
        string memory fullName = barStr;

        //
        // 2) COMPUTE ART PARAMETERS
        //
        // rows ← time (1–50)
        uint256 rows = m.time;
        if (rows < 1) rows = 1;
        if (rows > 50) rows = 50;

        // chars ← gasPrice (gwei) clamped 1–100
        uint256 chars = m.gasPrice / 1e9;
        if (chars < 1) chars = 1;
        if (chars > 100) chars = 100;

        // shade offset from txThroughput
        string[5] memory blocks = [
            unicode"⣿",
            unicode"⣶",
            unicode"⣤",
            unicode"⣀",
            unicode"⠁"
        ];
        uint8 shadeOffset = uint8(4 - (m.txThroughput % 5));

        //
        // 3) BUILD SVG <text> WITH ONE <tspan> PER ROW
        //
        string memory svgText = string(
            abi.encodePacked(
                '<text x="10" y="20" xml:space="preserve" ',
                'style="white-space:pre;font-family:monospace;font-size:12px;">'
            )
        );

        for (uint256 y = 0; y < rows; y++) {
            uint8 idx = uint8((shadeOffset + y) % 5);
            string memory ch = blocks[idx];

            // build a row of `chars` copies of `ch`
            string memory row;
            for (uint256 x = 0; x < chars; x++) {
                row = string(abi.encodePacked(row, ch));
            }

            if (y == 0) {
                svgText = string(
                    abi.encodePacked(svgText, '<tspan x="10" dy="0em">', row, '</tspan>')
                );
            } else {
                svgText = string(
                    abi.encodePacked(svgText, '<tspan x="10" dy="1.2em">', row, '</tspan>')
                );
            }
        }
        svgText = string(abi.encodePacked(svgText, "</text>"));

        //
        // 4) WRAP IT IN AN SVG
        //
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600">',
                '<rect width="100%" height="100%" fill="#fff"/>',
                svgText,
                "</svg>"
            )
        );
        string memory image = string(
            abi.encodePacked(
                "data:image/svg+xml;base64,",
                Base64.encode(bytes(svg))
            )
        );

        //
        // 5) JSON METADATA
        //
        bytes memory meta = abi.encodePacked(
            '{"name":"', fullName,
            '","description":"ASCII-Eval NFT: on-chain metrics -> art","image":"', image,
            '","attributes":[',
              '{"trait_type":"bars","value":', bars.toString(), '},',
              '{"trait_type":"time","value":', m.time.toString(), '},',
              '{"trait_type":"gaslimit","value":', m.gaslimit.toString(), '},',
              '{"trait_type":"gasPrice","value":', m.gasPrice.toString(), '},',
              '{"trait_type":"priorityFee","value":', m.priorityFee.toString(), '},',
              '{"trait_type":"txThroughput","value":', m.txThroughput.toString(), '}',
            ']}'
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(meta)
            )
        );
    }

    receive() external payable {}
    fallback() external payable {}
}
