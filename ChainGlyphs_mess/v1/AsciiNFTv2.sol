// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";  
import "@openzeppelin/contracts/access/Ownable.sol";  
import "@openzeppelin/contracts/utils/Counters.sol";  
import "@openzeppelin/contracts/utils/Strings.sol";  
import "@openzeppelin/contracts/utils/Base64.sol";  

/// @title AsciiChainEvalNFT (keccak256, 60-wide, avg-glyphs per row)
contract AsciiChainEvalNFT is ERC721, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;

    struct Metrics {
        uint256 time;
        uint256 gaslimit;
        uint256 baseFee;
        uint256 gasPrice;
        uint256 priorityFee;
        uint256 chainId;
        uint256 diskSize;
        uint256 txThroughput;
        uint256 archiveSize;
    }

    Counters.Counter private _tokenIdCounter;
    uint256 public mintPrice;
    uint256 public maxSupply;
    mapping(address=>bool) public minters;
    mapping(uint256=>Metrics) private _metrics;

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

    /// Phase 1: emit on-chain metrics & mint stub
    function safeMintWithMetrics(address to) external payable onlyMinter {
        uint256 id = _tokenIdCounter.current();
        require(id < maxSupply,       "Exceeds max supply");
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

    /// Phase 2: store metrics & mint final
    function safeMintWithParams(
        address    to,
        uint256    time,
        uint256    gaslimit,
        uint256    baseFee,
        uint256    gasPrice,
        uint256    priorityFee,
        uint256    chainId,
        uint256    diskSize,
        uint256    txThroughput,
        uint256    archiveSize
    ) external payable onlyMinter {
        uint256 id = _tokenIdCounter.current();
        require(id < maxSupply,       "Exceeds max supply");
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
    }

    function setMinter(address who, bool allowed) external onlyOwner {
        minters[who] = allowed;
    }
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function getMetrics(uint256 tokenId) external view returns (Metrics memory) {
        require(_exists(tokenId), "Nonexistent token");
        return _metrics[tokenId];
    }

    /// @notice Build SVG + JSON metadata
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Nonexistent token");
        Metrics memory m = _metrics[tokenId];

        // — name = bars from gaslimit/12M
        uint256 bars = m.gaslimit / 12_000_000;
        if (bars < 1)  bars = 1;
        if (bars > 50) bars = 50;
        string memory barStr;
        for (uint256 i; i<bars; i++){
            barStr = string(abi.encodePacked(barStr, "|"));
        }

        // — rows = time clamped 1–41
        uint256 rows = m.time < 1 ? 1 : (m.time > 41 ? 41 : m.time);

        // — fixed width = 60
        uint256 cols = 82;

        // — average glyphs per row = gasPrice(gwei) clamped 1–60
        uint256 avg = m.gasPrice / 1e9;
        if (avg < 1)   avg = 1;
        if (avg > 82)  avg = 82;

        // — shade offset
        uint8 shadeOffset = uint8(4 - (m.txThroughput % 5));

        // — block characters
        string[5] memory blocks = [
            unicode"⣿", unicode"⣶",
            unicode"⣤", unicode"⣀",
            unicode"⠁"
        ];

        // — seed
        bytes32 seed = keccak256(
            abi.encodePacked(tokenId, m.time, m.gasPrice, m.txThroughput)
        );

        // — build <text> with one <tspan> per row
        string memory svgText = string(
            abi.encodePacked(
              '<text x="10" y="20" xml:space="preserve" ',
              'style="white-space:pre;font-family:monospace;font-size:12px;">'
            )
        );

        for (uint256 y; y<rows; y++) {
            string memory row;
            for (uint256 x; x<cols; x++) {
                // decide glyph vs space
                bytes32 cellHash = keccak256(abi.encodePacked(seed, y, x));
                bool drawGlyph = (uint8(cellHash[0]) % 60) < avg;
                if (drawGlyph) {
                    // choose shade
                    uint8 idx = uint8((uint256(cellHash) + shadeOffset) % 5);
                    row = string(abi.encodePacked(row, blocks[idx]));
                } else {
                    row = string(abi.encodePacked(row, " "));
                }
            }
            // tspan per row
            if (y==0) {
                svgText = string(abi.encodePacked(
                  svgText,
                  '<tspan x="10" dy="0em">', row, '</tspan>'
                ));
            } else {
                svgText = string(abi.encodePacked(
                  svgText,
                  '<tspan x="10" dy="1.2em">', row, '</tspan>'
                ));
            }
        }
        svgText = string(abi.encodePacked(svgText,"</text>"));

        // — wrap SVG
        string memory svg = string(abi.encodePacked(
          '<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600">',
            '<rect width="100%" height="100%" fill="#fff"/>',
            svgText,
          '</svg>'
        ));
        string memory image = string(abi.encodePacked(
          "data:image/svg+xml;base64,",
          Base64.encode(bytes(svg))
        ));

        // — metadata
        bytes memory meta = abi.encodePacked(
          '{"name":"', barStr,
          '","description":"ASCII-Eval NFT: on-chain metrics -> art",',
          '"image":"', image, '","attributes":[',
            '{"trait_type":"bars","value":',      bars.toString(),        '},',
            '{"trait_type":"time","value":',      m.time.toString(),      '},',
            '{"trait_type":"gaslimit","value":',  m.gaslimit.toString(),  '},',
            '{"trait_type":"gasPrice","value":',  m.gasPrice.toString(),  '},',
            '{"trait_type":"priorityFee","value":',m.priorityFee.toString(),' },',
            '{"trait_type":"txThroughput","value":',m.txThroughput.toString(),'}',
          ']}'
        );
        return string(abi.encodePacked(
          "data:application/json;base64,",
          Base64.encode(meta)
        ));
    }

    receive() external payable {}
    fallback() external payable {}
}
