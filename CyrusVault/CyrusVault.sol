// SPDX-License-Identifier: MIT
//9ecc02a53f8032a599c51cbc7f7c474835c40cb0e92543f7995708cce9e06df9
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IPancakePositionManager.sol";
import "../interfaces/ICyrusPositionManager.sol";



contract CyrusVault is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public constant USDT = IERC20(0x55d398326f99059fF775485246999027B3197955);
    IPancakePositionManager public constant PancakePositionManager = IPancakePositionManager(0x46A15B0b27311cedF172AB29E4f4766fbE7F4364);

    uint256 constant public MIN_POSITION_AMOUNT = 10 ether;

    ICyrusPositionManager public CyrusPositionManager;

    uint256[] private tokenIds;
    uint256[] private strategies;

    //user address => invited by
    mapping(address => address) private affiliates;
    mapping(address => mapping(uint256 => uint256)) private affiliatesNumber;
    mapping(address => uint256) private affiliatesTurnover;

    event PositionOpened(address indexed user, uint256 amount, uint256 timestamp, uint256 tokenId);

    constructor() Ownable(msg.sender) {
        (bool success, bytes memory data) = address(USDT).call(
            abi.encodeWithSelector(USDT.approve.selector, address(PancakePositionManager), type(uint256).max)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Approve failed");
    }

    function openPosition(uint256 usdtAmount, uint256 strategyId, address affiliate) external{
        require(address(CyrusPositionManager) != address(0));
        require(strategyId < strategies.length, "Strategy not found");
        require(usdtAmount > 0, "Invalid usdtAmount");
        require(tokenIds.length > 0, "No tokenIds");
        require(usdtAmount >= MIN_POSITION_AMOUNT, "Position too small");

        USDT.safeTransferFrom(msg.sender, address(this), usdtAmount);
       
        _openPosition(usdtAmount, strategyId, msg.sender, affiliate);

        
    }

    function _openPosition(uint256 usdtAmount, uint256 strategyId, address to, address affiliate) internal {
        setAffiliate(affiliate, usdtAmount);

        uint256 tokenId = CyrusPositionManager.mint(to, MintCyrusParams({
            strategyId: strategyId,
            amount: usdtAmount,
            start: block.timestamp,
            finish: block.timestamp + strategies[strategyId]
           
        }));

        uint256 len = tokenIds.length;
        uint256 share = usdtAmount / len;
        uint256 remainder = usdtAmount % len;
        

        for(uint256 i = 0; i < len; i++) {
            uint256 amountToAdd = share;
            if(i == 0) {  
                amountToAdd += remainder; 
            }
            increaseLiquidity(tokenIds[i], amountToAdd);
        }

        emit PositionOpened(to, usdtAmount, block.timestamp,tokenId);
    }


    function setAffiliate(address _affiliate, uint256 _positionAmount) internal {
    bool isFirstDeposit = CyrusPositionManager.tokensOfOwner(msg.sender).length == 0;

    if (isFirstDeposit) {
        if (_affiliate == address(0) || _affiliate == msg.sender) return;
        if (affiliates[msg.sender] != address(0)) return;

        address upline = _affiliate;

        for (uint256 level = 0; level < 20; level++) {
            if (upline == address(0)) break;

            if (upline == msg.sender) return;

            affiliatesNumber[upline][level] += 1;

            upline = affiliates[upline];
        }

        affiliates[msg.sender] = _affiliate;
    }

        address referrer = affiliates[msg.sender];
        for (uint256 i = 0; i < 20; i++) {
            if (referrer == address(0)) break;
            affiliatesTurnover[referrer] += _positionAmount;
            referrer = affiliates[referrer];
        }
    }
    /**
 * @notice Adds USDT liquidity to an existing Pancake position with up to 0.5% slippage tolerance.
 * @dev The actual added liquidity may be slightly less than the requested amount due to price movement
 *      or rounding errors. A 0.5% slippage tolerance is applied to prevent unnecessary reverts.
 * @param tokenId The Pancake position NFT ID to which liquidity should be added.
 * @param usdtAmountWithSlippage The target USDT amount to add (up to 0.5% slippage accepted).
 */
   function increaseLiquidity(uint256 tokenId, uint256 usdtAmountWithSlippage) internal {
    (
        ,
        ,
        address token0,
        address token1,
        ,
        ,
        ,
        ,
        ,
        ,
        ,
    ) = PancakePositionManager.positions(tokenId);

    bool usdtIsToken0;
    if (token0 == address(USDT)) {
        usdtIsToken0 = true;
    } else if (token1 == address(USDT)) {
        usdtIsToken0 = false;
    } else {
        revert("USDT not in position");
    }

    // Allow 0.5% slippage: minAmount = 99.5% of requested amount
    uint128 minAmount = uint128((usdtAmountWithSlippage * 995) / 1000);

    uint128 amount0Desired = usdtIsToken0 ? uint128(usdtAmountWithSlippage) : 0;
    uint128 amount1Desired = usdtIsToken0 ? 0 : uint128(usdtAmountWithSlippage);
    uint128 amount0Min = usdtIsToken0 ? minAmount : 0;
    uint128 amount1Min = usdtIsToken0 ? 0 : minAmount;

    (
        ,
        uint256 amount0,
        uint256 amount1
    ) = PancakePositionManager.increaseLiquidity(
        IncreaseLiquidityParams({
            tokenId: tokenId,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp
        })
    );

    require(amount0 > 0 || amount1 > 0, "IncreaseLiquidity failed");
    
    if (usdtIsToken0) {
        require(
            amount0 >= amount0Min,
            "Slippage exceeded: amount0 below permitted tolerance"
        );
    } else {
        require(
            amount1 >= amount1Min,
            "Slippage exceeded: amount1 below permitted tolerance"
        );
    }
   }

    function addStrategy(uint256 durationUnix) public onlyOwner {
        require(durationUnix > 0);
        strategies.push(durationUnix);
    }

    function removeStrategy(uint256 index) public onlyOwner {
        require(index < strategies.length, "Index out of range");

        for (uint256 i = index; i < strategies.length - 1; i++) {
            strategies[i] = strategies[i + 1];
        }

        strategies.pop();
    }   


    function addPositionManager(address _CyrusPositionManager) public onlyOwner {
        require(_CyrusPositionManager != address(0));
        require(address(CyrusPositionManager) == address(0));

        CyrusPositionManager = ICyrusPositionManager(_CyrusPositionManager);
    }

    function addTokenId(uint256 _tokenId) public onlyOwner {
        require(_tokenId > 0, "Invalid tokenId");
        require(!isTokenIdExist(_tokenId), "TokenId already exist");

        tokenIds.push(_tokenId);
    }

    function setTokenIdByIndex(uint256 index,uint256 _tokenId) public onlyOwner {
        require(index < tokenIds.length, "Index out of range");
        require(_tokenId > 0, "Invalid tokenId");
        require(!isTokenIdExist(_tokenId) , "TokenId already exist");
        tokenIds[index] = _tokenId;
    }

    function removeTokenIdByIndex(uint256 index) public onlyOwner {
        require(index < tokenIds.length, "Index out of range");

        for (uint256 i = index; i < tokenIds.length - 1; i++) {
            tokenIds[i] = tokenIds[i + 1];
        }

        tokenIds.pop();
        
    }

    function isTokenIdExist(uint256 _tokenId) internal view returns (bool) {
        for(uint256 i = 0; i < tokenIds.length; i++) {
            if(tokenIds[i] == _tokenId) {
                return true;
            }
        }
        return false;
    }

    function getTokenIds() external view onlyOwner returns (uint256[] memory) {
        return tokenIds;
    }

    function getStrategies() external view returns (uint256[] memory) {
        return strategies;
    }

    function getAffiliate(address addr) external view returns (address) {
        return affiliates[addr];
    }

    function getAffiliatesNumber(address addr) external view returns (uint256[] memory) {
        uint256[] memory _affiliatesNumber = new uint256[](20);
        for(uint256 i = 0; i < 20; i++) {
            _affiliatesNumber[i] = affiliatesNumber[addr][i];
        }
        return _affiliatesNumber;
    }

    function getAffiliateTurnover(address addr) external view returns (uint256) {
        return affiliatesTurnover[addr];
    }

}

