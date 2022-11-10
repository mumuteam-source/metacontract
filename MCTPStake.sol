// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";



/**
 * @title  MetaCraftTrade
 * * @notice Implements the Trade of NFT Market. The market will be governed
 * by an ERC20 token as currency, and an ERC721 token that represents the
 * ownership of the items being traded. Only ads for selling items are
 * implemented. The item tokenization is responsibility of the ERC721 contract
 * which should encode any item details.
 */
contract MCTPStake is Pausable {
      
    using SafeMath for uint256;
    string public name;
    uint256 public stakeNum;
    uint256 public minStakeAmount;
    uint256 public safeDuration = 14;
      
  
    event StakeStatusChange(
       address itemToken,
       uint256 tokenAmount, 
	   string status,
	   address staker,
       uint256 timestamp
	   );

   address private owner;

    struct Stake {
        address itemToken;
        uint256 tokenAmount;
        address staker;
        uint256 timestamp;
    }


   
    // stakes[tokenAddress][stakerAddress]==>Stake
    mapping(address => mapping(address => Stake)) public stakes;
    mapping(string  => address) public tokens;

    address payable public withdrawAddress = payable(address(0x36544C1819F99607f0e2CDfE582Bb143453459bc));
    event StakeEvents(
        uint256 timeStamp,
        address eventSender,          
        string  eventName
    );
 
    constructor ()
    {    
        name = "MCTPStakeTEST";
        owner = msg.sender;
    }
    function setParamaters ( address _withdrawAddress,uint256 _minStakeAmount,uint256 _safeDuration)
    public
    whenNotPaused
    {
        require(msg.sender==owner,"Only owner can set Rent Rate");
        withdrawAddress = payable(_withdrawAddress);
        minStakeAmount = _minStakeAmount;
        safeDuration = _safeDuration;
        emit StakeEvents(block.timestamp,msg.sender, "setParamaters");
    }

    function pause() public  {
        require(msg.sender == owner,"Only the owner of this Contract could do It!");
        _pause();
        emit StakeEvents(block.timestamp,msg.sender, "pause");
    }

    function unpause() public {
        require(msg.sender == owner,"Only the owner of this Contract could do It!");
        _unpause();
        emit StakeEvents(block.timestamp,msg.sender, "unpause");
    }
   
    /**
     * @dev Returns the details for a trade.
     * @param staker The id for the item trade.
     */
    function getStake(address itemToken,address staker)
        public
        virtual
        view
        returns(Stake memory stake,uint256)
    {
        stake = stakes[itemToken][staker];
        return (stake,stakeNum);
    }
    function stakerBalance(address itemToken, address staker)
        public 
        virtual 
        view 
        returns (uint256)
    {
        Stake memory stake = stakes[itemToken][staker];
        return stake.tokenAmount;
    }
    /*
     * @dev Opens a new trade. Puts _item in escrow.
     * @param _item The id for the item to trade.
     * @param _price The of currency for which to trade the item.
     */
    function openStake(
        address _itemToken,
        uint256 _tokenAmount
        )
        public
        whenNotPaused
        virtual
    {
        //require(isStaked[_itemToken][_item]==false,"Already Staked Token");
        require(_tokenAmount >= minStakeAmount,"stake tokenAmount too small!");
        IERC20(_itemToken).transferFrom(msg.sender, address(this), _tokenAmount); 
        Stake storage oldstake = stakes[_itemToken][msg.sender];
        if(oldstake.staker == msg.sender){
            if(oldstake.tokenAmount==0) stakeNum++;
            oldstake.tokenAmount += _tokenAmount;
            oldstake.timestamp = block.timestamp;
        }else {
            Stake memory stake = 
                Stake({
                itemToken: _itemToken,
                staker: msg.sender,
                tokenAmount: _tokenAmount,
                timestamp:block.timestamp
            });
            stakes[_itemToken][msg.sender] = stake;
            stakeNum++;
        }
        emit StakeStatusChange(_itemToken,_tokenAmount, "Stake",msg.sender,block.timestamp);

    }

    
    /**
     * @dev unstake a token by the staker.
     * @param _tokenAmount The trade to be cancelled.
     */
    function unStake(address _itemToken,uint256 _tokenAmount)
        public
        whenNotPaused
        virtual
    {
        Stake storage stake = stakes[_itemToken][msg.sender];
        require(
            msg.sender == stake.staker,
            "Stake can be unstake only by the Owner of this Token."
        );
        require(
            stake.tokenAmount >=_tokenAmount,
            "Stake token Amount insufficient."
        );
        require(
           block.timestamp - stake.timestamp >=safeDuration * 1 minutes, 
           string(abi.encodePacked("Your Stake should be locked for ",safeDuration," Days"))
        );
        require(IERC20(_itemToken).approve(address(this), _tokenAmount), "Approve has failed"); 
        IERC20(_itemToken).transferFrom(address(this), stake.staker, _tokenAmount);
        stake.tokenAmount -= _tokenAmount;
        stake.timestamp = block.timestamp;
        if(stake.tokenAmount==0) stakeNum--;
        emit StakeStatusChange(_itemToken,_tokenAmount, "UnStake", msg.sender,block.timestamp);
    }
     
   
    /**
    **withdraw
    **
    **
    **/
    function totalBalance() external view returns(uint) {
    
     //emit AuctionEvents(block.timestamp,msg.sender, "totalBalance");
     return payable(address(this)).balance;
     }

   function withdrawFunds() external whenNotPaused withdrawAddressOnly() {
    
       //payable(msg.sender).transfer(this.totalBalance());
       Address.sendValue(payable(msg.sender),this.totalBalance());
       emit StakeEvents(block.timestamp,msg.sender, "withdrawFunds");
   }
   
   function withdrawFunds(address _itemToken) external whenNotPaused withdrawAddressOnly() {
     require(IERC20(_itemToken).approve(address(this), IERC20(_itemToken).balanceOf(address(this))), "Approve has failed"); 
     IERC20(_itemToken).transferFrom(address(this),msg.sender, IERC20(_itemToken).balanceOf(address(this)));
      // payable(msg.sender).transfer(this.totalBalance());
      emit StakeEvents(block.timestamp,msg.sender, "withdrawFunds Coin");
   }

   modifier withdrawAddressOnly() {
     require(msg.sender == withdrawAddress, 'only withdrawer can call this');
   _;
   }
 
   function destroy() virtual public {
	require(msg.sender == owner,"Only the owner of this Contract could destroy It!");
        if (msg.sender == owner) selfdestruct(payable(owner));
        
        
          
        emit StakeEvents(block.timestamp,msg.sender,"destory");
    }
   
   
   
}