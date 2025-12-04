// SPDX-License-Identifier: MIT
//9ecc02a53f8032a599c51cbc7f7c474835c40cb0e92543f7995708cce9e06df9

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CyrusPosition is ERC721, AccessControl, ReentrancyGuard {
    using Strings for uint256;

    struct PositionInfo{
        uint256 strategyId; // id of strategy
        uint256 amount; //amount of USDT in position
        uint256 start; // timestamp of opening position
        uint256 finish; // timestamp of closing position
        uint256 totalClaimed; // total amount of USDT claimed
        uint256 lastClaimed; // timestamp of last claim
        uint256 unclaimed; // unclaimed amount
    }

    struct MintParams {
        uint256 strategyId;
        uint256 amount;
        uint256 start;
        uint256 finish;
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");

    uint256 private _tokenIdCounter;

    string baseURI;

    // the list of positions
    mapping(uint256 => PositionInfo) public positions;

    // the list of tokens address own
    mapping(address => uint256[]) private _ownedTokens;

    // tokenId => index in _ownedTokens[owner]
    mapping(uint256 => uint256) private _ownedTokensIndex; 



    modifier onlyTreasuryOrEmergency() {
        require(
            hasRole(TREASURY_ROLE, msg.sender) || hasRole(EMERGENCY_MANAGER_ROLE, msg.sender),
            "Not authorized"
        );
        _;
    }


    constructor(address _minter, address _treasury, address _emergency) ERC721("CyrusPosition", "BNP") {

        require(_minter != address(0), "Invalid minter");
        require(_treasury != address(0) , "Invalid treasury");
        require(_emergency != address(0), "Invalid emergency manager");

        _addMinter(_minter);
        _addTreasury(_treasury);
        _addEmergencyManager(_emergency);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function mint(address to, MintParams calldata params) external onlyRole(MINTER_ROLE) nonReentrant returns(uint256) {
        uint256 tokenId = _tokenIdCounter;


        positions[tokenId] = PositionInfo(
            {
                strategyId: params.strategyId, 
                amount: params.amount, 
                start: params.start, 
                finish: params.finish,
                totalClaimed: 0,
                lastClaimed: 0,
                unclaimed: 0
            }
        );


        _safeMint(to, tokenId);

        _tokenIdCounter++;


        return tokenId;
    }

    function updatePosition(uint256 tokenId, PositionInfo calldata params) external onlyTreasuryOrEmergency {
        _requireOwned(tokenId);

        positions[tokenId] = params;
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address from) {
        from = super._update(to, tokenId, auth);

        if (from != address(0)) {
            uint256 lastTokenIndex = _ownedTokens[from].length - 1;
            uint256 tokenIndex = _ownedTokensIndex[tokenId];

            if (tokenIndex != lastTokenIndex) {
                uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
                _ownedTokens[from][tokenIndex] = lastTokenId;
                _ownedTokensIndex[lastTokenId] = tokenIndex;
            }

            _ownedTokens[from].pop();
            delete _ownedTokensIndex[tokenId];
        }

        if (to != address(0)) {
            _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
            _ownedTokens[to].push(tokenId);
        }
    }

    function burn(uint256 tokenId) public {
        address owner = ownerOf(tokenId);
        require(_isAuthorized(owner, msg.sender, tokenId), "Not approved nor owner");
        _burn(tokenId);
    }

    function setBaseURI(string memory _baseURI) public onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _baseURI; 
    }


    function _addMinter(address account) internal {
        _grantRole(MINTER_ROLE, account);
    }

    function _addEmergencyManager(address account) internal {
        _grantRole(EMERGENCY_MANAGER_ROLE, account);
    }

    function _addTreasury(address account) internal {
        _grantRole(TREASURY_ROLE, account);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);

        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString()) : "";
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter;
    }

    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        return _ownedTokens[owner];
    }

    function getPosition(uint256 tokenId) external view returns (PositionInfo memory) {
        return positions[tokenId];
    }

    function getPositions(uint256[] calldata tokenIds ) external view returns (PositionInfo[] memory) {
        PositionInfo[] memory tmpPositions = new PositionInfo[](tokenIds.length);

        for(uint256 i = 0; i < tokenIds.length; i++) {
            tmpPositions[i] = positions[tokenIds[i]];
        }

        return tmpPositions;
    }

    function getPositionsValue(address addr) external view returns (uint256 value) {
        uint256[] memory tokenIds= _ownedTokens[addr];

        for(uint256 i = 0; i<tokenIds.length;i++) {
            if(positions[tokenIds[i]].finish > block.timestamp) {
                value+= positions[tokenIds[i]].amount;
            }   
        }
    }


    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}