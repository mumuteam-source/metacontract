// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";



/**
 * @title  MCTPStake
 * * @notice Implements the Trade of NFT Market. The market will be governed
 * by an ERC20 token as currency, and an ERC721 token that represents the
 * ownership of the items being traded. Only ads for selling items are
 * implemented. The item tokenization is responsibility of the ERC721 contract
 * which should encode any item details.
 */
contract MCTPStake is Pausable {
      
    using SafeMath for uint256;
    string public name;
    uint256 public minStakeAmount=10 * 10 ** 18;   
    
    uint256 public totalStakeAmount;   
    uint256 public payedProfits;
    bool public withDuration; //if True,unstake must not whthin the duration; Else, can unstake anytime
    
    bool private locked;
  
    event StakeStatusChange(
       address itemToken,
       uint256 tokenAmount, 
	   string status,
	   address staker,
       uint256 duration,
       uint256 timestamp
	   );

   address private owner;

    struct Stake {
        address itemToken;
        address staker;
        uint256 tokenAmount;
        uint256 duration;
        uint256 reward;
        uint256 timestamp;
    }

    //stakeAmounts[0],180,365==>Amount
    mapping(uint256 => uint256) public stakeAmounts;
    //[tokenAddress][userAddress][duration]==>Stake[]
    mapping(address => mapping(address => mapping(uint256=> Stake))) public stakes;
    mapping(address=>bool) private hasStake;

    address payable public withdrawAddress = payable(address(0x39bDeAFcda9d9A612D217CBfA9E90bB28D4D1d23));
    
    //APYs  for Half / One /Two Years of Staking
    uint256 public half_APY=7;
    uint256 public full_APY=10;
    uint256 public two_APY=15;

  
    uint256 public constant SECONDS_IN_DAY = 86400;

    event StakeEvents(
        uint256 timeStamp,
        address eventSender,          
        string  eventName
    );
 
    constructor ()
    {    
        name = "MCTPStake";
        owner = msg.sender;
        withDuration=true;
        locked = false;
    }
    function setParamaters ( address _withdrawAddress,uint256 _minStakeAmount)
    public
    whenNotPaused
    {
        require(msg.sender==owner,"Only owner can set Parameters");
        withdrawAddress = payable(_withdrawAddress);
        minStakeAmount = _minStakeAmount;
        emit StakeEvents(block.timestamp,msg.sender, "setParamaters");
    }

    /**
     ** Set APY
     **/
    function setAPY( uint256 _half, uint256 _full, uint256 _two)
    public
    whenNotPaused
    {
        require(msg.sender==owner,"Only owner can set Percents");
       
        half_APY = _half;
        full_APY = _full;
        two_APY = _two;
        emit StakeEvents(block.timestamp,msg.sender, "setAPY");
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

    function setWithDuration() public {
        require(msg.sender == owner,"Only the owner of this Contract could do It!");
        withDuration = !withDuration;
        emit StakeEvents(block.timestamp,msg.sender, "setWithDuration");
    }
   
    /**
     * @dev Returns the details for user Stake.
     * 
     */
    function getUserStake(address itemToken,address staker,uint256 duration)
        public
        virtual
        view
        returns(Stake memory stake)
    {
        stake = stakes[itemToken][staker][duration];
        uint256 oldDuration_in_days = (block.timestamp.sub(stake.timestamp)).div(SECONDS_IN_DAY); //SECONDS for REAL 
            
        uint256 stakeAPY = 0;
        if(duration == 180)
            stakeAPY = stake.tokenAmount.mul(half_APY).div(100).div(2); //half year
        if(duration == 365) 
            stakeAPY = stake.tokenAmount.mul(full_APY).div(100); // full year
        if(duration == 730)
            stakeAPY = stake.tokenAmount.mul(two_APY).div(100).mul(2); // two years should multiply by 2

        uint256 stakeProfit = stakeAPY.mul(oldDuration_in_days).div(duration);
        
        if (oldDuration_in_days >= duration) stake.reward = stakeAPY;
        else stake.reward = stakeProfit;
        
        return stake;
    }

    
    function getUserAllStake(address itemToken,address staker)
        public
        virtual
        view
        returns(uint256, Stake []memory)
    {
        uint256 userAmount = 0;
        Stake[] memory stake = new Stake[](7);
        stake[0] = stakes[itemToken][staker][0];
        stake[1] = stakes[itemToken][staker][30];
        stake[2] = stakes[itemToken][staker][60];
        stake[3] = stakes[itemToken][staker][90];
        stake[4] = stakes[itemToken][staker][180];
        stake[5] = stakes[itemToken][staker][365];
        stake[6] = stakes[itemToken][staker][730];

        for( uint256 i=0;i<7;i++){

            uint256 duration_in_days = (block.timestamp.sub(stake[i].timestamp)).div(SECONDS_IN_DAY); //SECONDs
            uint256 stakeProfit=0;
            uint256 stakeAPY = 0;
            uint256 duration = 1;
            if(i == 4) {
                duration = 180;
                stakeAPY = stake[i].tokenAmount.mul(half_APY).div(100).div(2); //half year
            }
            if(i == 5) {
                duration = 365;
                stakeAPY = stake[i].tokenAmount.mul(full_APY).div(100); // full year
            }    
            if(i == 6){
                duration = 730;
                stakeAPY = stake[i].tokenAmount.mul(two_APY).div(100).mul(2); // two years should multiply by 2
            }
                

            stakeProfit = stakeAPY.mul(duration_in_days).div(duration);
            
            if (duration_in_days >= duration) stake[i].reward = stakeAPY;
            else stake[i].reward = stakeProfit;
            
            userAmount +=stake[i].tokenAmount;
        }
    
        return (userAmount,stake);
    }

    function getStakeAmount() 
        public 
        virtual
        view 
        returns (uint256, uint256[] memory)
    {
        uint256[] memory  stakeamount = new uint256[](7);
        stakeamount[0]=stakeAmounts[0];
        stakeamount[1]=stakeAmounts[30];
        stakeamount[2]=stakeAmounts[60];
        stakeamount[3]=stakeAmounts[90];
        stakeamount[4]=stakeAmounts[180];
        stakeamount[5]=stakeAmounts[365];
        stakeamount[6]=stakeAmounts[730];
        return (totalStakeAmount,stakeamount);
    }
    function getTotalStakeAmount()
        public
        virtual
        view
        returns (uint256)
       {
           return totalStakeAmount;
       } 
    function getStakeStatus (address _tokenAddress)
        public
        virtual
        view
        returns (bool)
      {
        return hasStake[_tokenAddress];
      }  
    function getPayedProfits()
            public
            virtual
            view
            returns (uint256)
        {
            return payedProfits;
        } 
    
    /*
     * 
     */
    function openStake(
        address _itemToken,
        uint256 _tokenAmount,
        uint256 _duration
        )
        public
        whenNotPaused
        virtual
    {
       
        require(_tokenAmount >= minStakeAmount,"stake tokenAmount too small!");
        require(IERC20(_itemToken).approve(address(this), _tokenAmount), "Approval failed"); 
        IERC20(_itemToken).transferFrom(msg.sender, address(this), _tokenAmount); 
        Stake storage oldstake = stakes[_itemToken][msg.sender][_duration];
        
        // stake more coins for a staking stage
        if(oldstake.staker == msg.sender){
            
            require(_tokenAmount >=  oldstake.tokenAmount, "stake Amount cant not less then current Amount!");

            uint256 oldDuration_in_days = (block.timestamp.sub(oldstake.timestamp)).div(SECONDS_IN_DAY); //SECONDS_IN_DAY
            
            uint256 stakeAPY = 0;
            uint256 stakeProfit=0;
            if(_duration == 180)
                stakeAPY = oldstake.tokenAmount.mul(half_APY).div(100).div(2); //half year
            if(_duration == 365) 
                stakeAPY = oldstake.tokenAmount.mul(full_APY).div(100); // full year
            if(_duration == 730)
                stakeAPY = oldstake.tokenAmount.mul(two_APY).div(100).mul(2); // two years should multiply by 2

             
            if (oldDuration_in_days>=_duration) stakeProfit=stakeAPY;
            else stakeProfit = stakeAPY.mul(oldDuration_in_days).div(_duration);


            payedProfits += stakeProfit;
            require(IERC20(_itemToken).approve(address(this), stakeProfit), "Approve has failed"); 
            IERC20(_itemToken).transferFrom(address(this), oldstake.staker, stakeProfit);

            oldstake.tokenAmount += _tokenAmount;
            oldstake.reward = 0;
            oldstake.timestamp = block.timestamp;
        }else {
            Stake memory stake = 
                Stake({
                itemToken: _itemToken,
                staker: msg.sender,
                tokenAmount: _tokenAmount,
                duration: _duration,
                reward:0,
                timestamp:block.timestamp
            });
            stakes[_itemToken][msg.sender][_duration] = stake;
        }

        totalStakeAmount+=_tokenAmount;
        stakeAmounts[_duration]+=_tokenAmount;
        hasStake[msg.sender] = true;
        emit StakeStatusChange(_itemToken,_tokenAmount, "Stake",msg.sender,_duration,block.timestamp);

    }
    // upgrade stake need not transfer MCTP in to contract, Just Upgrade the Plan from lower duration to higher Duration Level
    function upgradeStake(
        address _itemToken,
        uint256 _tokenAmount,
        uint256 _oldDuration,
        uint256 _newDuration
        )
        public
        whenNotPaused
        virtual
    {
        
        require(_tokenAmount >= minStakeAmount,"stake tokenAmount too small!");

        //IERC20(_itemToken).transferFrom(msg.sender, address(this), _tokenAmount); 
        Stake storage oldstake = stakes[_itemToken][msg.sender][_oldDuration];
        Stake storage newstake = stakes[_itemToken][msg.sender][_newDuration];
        require(oldstake.staker == msg.sender, "staker address has no stake before in this duration");
       

        oldstake.tokenAmount -= _tokenAmount;
        
        uint256 oldDuration_in_days = (block.timestamp.sub(oldstake.timestamp)).div(SECONDS_IN_DAY); ///Seconds
            
        uint256 stakeAPY = 0;
        uint256 stakeProfit=0;
        if(_oldDuration == 180)
            stakeAPY = oldstake.tokenAmount.mul(half_APY).div(100).div(2); //half year
        if(_oldDuration == 365) 
            stakeAPY = oldstake.tokenAmount.mul(full_APY).div(100); // full year
        if(_oldDuration == 730)
            stakeAPY = oldstake.tokenAmount.mul(two_APY).div(100).mul(2); // two years should multiply by 2
        
        if (oldDuration_in_days>=_oldDuration) stakeProfit=stakeAPY;
        else stakeProfit = stakeAPY.mul(oldDuration_in_days).div(_oldDuration);
       
        payedProfits += stakeProfit;
        require(IERC20(_itemToken).approve(address(this), stakeProfit), "Approve has failed"); 
        IERC20(_itemToken).transferFrom(address(this), oldstake.staker, stakeProfit);
        oldstake.reward = 0;
        //totalStakeAmount -=_tokenAmount;
       if(newstake.staker == msg.sender){

             require(_tokenAmount >=  newstake.tokenAmount, "stake Amount cant not less then current Amount!");
            //the new stake reward until this transaction: 
            uint256 newDuration_in_days = (block.timestamp.sub(newstake.timestamp)).div(SECONDS_IN_DAY); ///Seconds     
            uint256 newstakeAPY = 0;
            uint256 newstakeProfit=0;
            if(newDuration_in_days == 180)
                newstakeAPY = newstake.tokenAmount.mul(half_APY).div(100).div(2); //half year
            if(newDuration_in_days == 365) 
                newstakeAPY = newstake.tokenAmount.mul(full_APY).div(100); // full year
            if(newDuration_in_days == 730)
                newstakeAPY = newstake.tokenAmount.mul(two_APY).div(100).mul(2); // two years should multiply by 2
            
            if (newDuration_in_days>=_newDuration) newstakeProfit=newstakeAPY;
            else newstakeProfit = newstakeAPY.mul(newDuration_in_days).div(_newDuration);
        
            payedProfits += newstakeProfit;
            require(IERC20(_itemToken).approve(address(this), newstakeProfit), "Approve has failed"); 
            IERC20(_itemToken).transferFrom(address(this), newstake.staker, newstakeProfit);

            newstake.tokenAmount += _tokenAmount;
            newstake.reward = 0;
            newstake.timestamp = block.timestamp;
        }else {
            Stake memory stake = 
                Stake({
                itemToken: _itemToken,
                staker: msg.sender,
                tokenAmount: _tokenAmount,
                duration: _newDuration,
                reward : 0,
                timestamp:block.timestamp
            });
            stakes[_itemToken][msg.sender][_newDuration] = stake;
        }
        //totalStakeAmount+=_tokenAmount;
        stakeAmounts[_newDuration]+=_tokenAmount;
        stakeAmounts[_oldDuration]-=_tokenAmount;
        emit StakeStatusChange(_itemToken,_tokenAmount, "UpgradeStake",msg.sender,_newDuration,block.timestamp);

    }

    /**
     * @dev unstake a token by the staker.
     * @param _tokenAmount The trade to be cancelled.
     */
    function unStake(address _itemToken,uint256 _tokenAmount,uint256 _duration)
        public
        whenNotPaused
        noReentrancy //anti re-entrancy
        notContract(msg.sender) //anti contract address
        virtual
    {
        Stake storage stake = stakes[_itemToken][msg.sender][_duration];
        require(
            msg.sender == stake.staker,
            "Stake can be unstake only by the Owner of this Token."
        );
        require(
            stake.tokenAmount >=_tokenAmount,
            "Stake token Amount insufficient."
        );
        if(withDuration){
            require(
            block.timestamp - stake.timestamp >= _duration * 1 days,    //days for real project 
            string(abi.encodePacked("UnStake should be More than ",_duration," Days"))
            );
        }
        
        uint256 payprofit = 0;
        if(_duration == 180)
            payprofit = _tokenAmount.mul(half_APY).div(100).div(2);  //half of year should divided by 2
        if(_duration == 365) 
            payprofit = _tokenAmount.mul(full_APY).div(100);         // full year
        if(_duration == 730)
           payprofit = _tokenAmount.mul(two_APY).div(100).mul(2);  // two years should multiply by 2
        
        payedProfits += payprofit;
        uint256 payAmount =  _tokenAmount.add(payprofit);
        require(IERC20(_itemToken).approve(address(this), payAmount), "Approve has failed");      
        IERC20(_itemToken).transferFrom(address(this), stake.staker, payAmount);

        stake.tokenAmount -= _tokenAmount;
        stake.reward = 0;
        stake.timestamp = block.timestamp;

        totalStakeAmount-=_tokenAmount;
        stakeAmounts[_duration]-=_tokenAmount;
        emit StakeStatusChange(_itemToken,_tokenAmount, "UnStake", msg.sender,_duration,block.timestamp);
    }
    
    /**
     * @dev restake a token by the staker.
     * The trade to be reStake.
     */
    function reStake(address _itemToken,uint256 _duration)
        public
        whenNotPaused
        noReentrancy //anti re-entrancy
        notContract(msg.sender) //anti contract address
        virtual
    {
        Stake storage stake = stakes[_itemToken][msg.sender][_duration];
        require(
            msg.sender == stake.staker,
            "Stake can be retake only by the Owner of this Token."
        );
        uint256 _tokenAmount = stake.tokenAmount;
        if(withDuration){
            require(
            block.timestamp - stake.timestamp >= _duration * 1 days,    //days for real project 
            string(abi.encodePacked("reStake should be More than ",_duration," Days"))
            );
        }
        uint256 payprofit = 0;
       if(_duration == 180)
            payprofit = _tokenAmount.mul(half_APY).div(100).div(2);  //half of year 
        if(_duration == 365) 
            payprofit = _tokenAmount.mul(full_APY).div(100);         // full year
        if(_duration == 730)
           payprofit = _tokenAmount.mul(two_APY).div(100).mul(2);  // two years

        payedProfits += payprofit;
        require(IERC20(_itemToken).approve(address(this), payprofit), "Approve has failed"); 
        IERC20(_itemToken).transferFrom(address(this), stake.staker, payprofit);

        Stake memory newstake = 
                Stake({
                itemToken: _itemToken,
                staker: msg.sender,
                tokenAmount: _tokenAmount,
                duration: _duration,
                reward : 0,
                timestamp:block.timestamp
            });
        
        stakes[_itemToken][msg.sender][_duration] = newstake;

        emit StakeStatusChange(_itemToken,_tokenAmount, "ReStake", msg.sender,_duration,block.timestamp);
    }

    function depositMCTP(address _MCTPAddress, uint256 depositAmount) 
    public
    {
         require(IERC20(_MCTPAddress).approve(address(this), depositAmount), "Approve has failed"); 
         IERC20(_MCTPAddress).transferFrom(msg.sender,address(this), depositAmount); 
         emit StakeEvents(block.timestamp,msg.sender, "Deposit MCTP Coin");
    }
    
    function getMCTPBalance(address _MCTPAddress) public view returns(uint256) {
        return IERC20(_MCTPAddress).balanceOf(address(this));
    }

 
    /**
    **withdraw token
    **/
   
   function withdrawFunds(address _itemToken) external whenNotPaused withdrawAddressOnly() {
        require(IERC20(_itemToken).approve(address(this), IERC20(_itemToken).balanceOf(address(this))), "Approve has failed"); 
        IERC20(_itemToken).transferFrom(address(this),msg.sender, IERC20(_itemToken).balanceOf(address(this)));
        
        emit StakeEvents(block.timestamp,msg.sender, "withdrawFunds Coin");
   }

   modifier withdrawAddressOnly() {
        require(msg.sender == withdrawAddress, "only withdrawer can call this");
        _;
   }

    //anti re entranccy
    //lock
    modifier noReentrancy() {
            require(!locked, "Reentrant call detected!");
            locked = true;
            _;
            locked = false;
    }
    //not contract address
    //codesize
    modifier notContract(address _address) {
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(_address)
            }
            require(codeSize == 0, "Contracts are not allowed to receive tokens");
            _;
    }
 
   function destroy() virtual public {
        require(msg.sender == owner,"Only the owner of this Contract could destroy It!");
        if (msg.sender == owner) selfdestruct(payable(owner));
        emit StakeEvents(block.timestamp,msg.sender,"destory");
        }
   
}