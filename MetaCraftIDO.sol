// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./MCTPStake.sol";

/**
 * @title MetaCraftIDO
 *
 */
contract MetaCraftIDO is Ownable{
    using SafeMath for uint256;
    string public name;
    address payable public withdrawAddress;
    address public projectCoinAddress;
    address public investCoinAddress;
    uint256 public investTargetAmount;  //BUSD or USDT target Amount;
    uint256 public projectCoinPrice=10**16; //0.01;
    uint256 public startTimestamp = 1667808000;
    uint256 public investorNum;
    Investor []  public investors;
    uint256 public decimals=18;
    uint256 public safeDuration = 10;
    bool public isIssued = false;
    uint256 public projectCoinAmount = 0;
    uint256 public investedAmount = 0;
    uint256 public claimedAmount =0;
    uint256 public platformFee = 500;
    uint256 public feeBase = 10000;
    address payable public platformAddress = payable(address(0x36544C1819F99607f0e2CDfE582Bb143453459bc));
    string public hashCode;
    
    // stake Address;
    MCTPStake public stakeAddress = MCTPStake(0x2f3AB5a9E22ca2F2f9bb1b83f3fc76604dC6Dd9E);
    
    //IERC20 CoinToken; //Do not use currency Token just now
    
    struct Investor {
        address investCoinAddress; //usdt or BUSD contract address;
        address payable investorAddress;
        uint256 investedCoinAmount;  // user invest USDT or BUSD amount
        uint256 claimedProjectCoinAmount; //projectCoin Amount
        uint256 investedAt;
        uint256 claimedAt;
    }

   
    mapping(address => Investor) public investorByAddress;
    /**
     */
    event IDOEvents(
        uint256 timeStamp,
        address eventSender,          
        string  eventName
    );
    event IDOStatusChange(
       address indexed itemToken,
       uint256 indexed tokenAmount, 
       address indexed eventSender,
	   string status
	   
	   );

    constructor (string memory projectName, address investCoinAddress_, string memory hashCode_)
    {
       	name = projectName;
        investCoinAddress = investCoinAddress_;
        hashCode = hashCode_;
    }
    function setWithdrawAddress (address withDrawTo_) external onlyOwner{
        withdrawAddress = payable(withDrawTo_);
        emit IDOEvents(block.timestamp, msg.sender, "SetWithDrawAddress");
    }
    function  setParameters (string memory  projectName,
                             uint256 _targetAmount, 
                             uint256 _tokenPrice,
                             uint256 _startTimestamp, 
                             uint256 _safeDuration,
                             address _investCoinAddress,
                             uint256 _platformFee)
    public 
    onlyOwner
    {
       	name = projectName;
    	//owner = msg.sender;
        investTargetAmount = _targetAmount;
        projectCoinPrice = _tokenPrice;
        startTimestamp = _startTimestamp;
        safeDuration = _safeDuration; // in hours;
        investCoinAddress = _investCoinAddress;
        platformFee = _platformFee;
        emit IDOEvents(block.timestamp, msg.sender, "set Parameters");
    }
    function setStakeAddress (address stakeAddress_)
    public 
    onlyOwner
    {
        stakeAddress = MCTPStake(stakeAddress_);
        emit IDOEvents(block.timestamp, msg.sender, "setStakeAddress");
    }
    /*
    * @_tokenAddress : the BUSD or USDT contractAddress;
    * @tokenAmounts_: the token Amount want to invest;
    */
   
    function getStakedBalance(address _tokenAddress, address _owner)
    public 
    virtual 
    view 
    returns (uint256)
    {
        return stakeAddress.stakerBalance(_tokenAddress, _owner);
    }
    function investIn(address _tokenAddress,address _MCTPAddress, uint256 tokenAmounts_,string memory hashCode_) public {
        require(keccak256(abi.encodePacked(hashCode_)) ==
            keccak256(abi.encodePacked(hashCode)),"Valid Code is not correct");
        require(investCoinAddress == _tokenAddress, "invest Coin Not Correct!");
        require(block.timestamp >= startTimestamp,"you should invest after the starting of IDO");  
        require(_tokenAddress != address(0),"Token not support Now");  
        require(tokenAmounts_ > 0,"you should deposit some coins of this token");  
        require(tokenAmounts_.mod(projectCoinPrice) ==0, "invest amount should be an integral multiple of the token Price"); 
        // get wether in whitelist from stake pool;
        require(getStakedBalance(_MCTPAddress,msg.sender)>= 100* 10**18, "now in whitlist");
        IERC20(_tokenAddress).transferFrom(msg.sender,address(this), tokenAmounts_);  
        Investor storage investor = investorByAddress [msg.sender];
        if(investor.investorAddress == msg.sender){
            require(investor.investCoinAddress == _tokenAddress, "The Coin Address incorrect!");
            investor.investedCoinAmount += tokenAmounts_;
            investor.investedAt = block.timestamp;
            for (uint256 i =0 ;i<investors.length;i++){
                if (investors[i].investorAddress == msg.sender)
                {
                    investors[i].investedCoinAmount += tokenAmounts_;
                    investors[i].investedAt = block.timestamp;
                }
            }

        }else {
            Investor memory inv;
            inv.investCoinAddress = _tokenAddress;
            inv.investorAddress = payable(msg.sender);
            inv.investedCoinAmount += tokenAmounts_;
            inv.investedAt = block.timestamp;
            investorByAddress[msg.sender]=inv;
            investors.push(inv);
            investorNum += 1;

        }
        investedAmount += tokenAmounts_;
      

        
        emit IDOEvents(block.timestamp, msg.sender, "invest Coin");
        emit IDOStatusChange(_tokenAddress, tokenAmounts_, msg.sender, "Invest");
    }
    
    function refundOut(address tokenAddress_, uint256 tokenAmounts_,string memory hashCode_) public {
        require(keccak256(abi.encodePacked(hashCode_)) ==
            keccak256(abi.encodePacked(hashCode)),"Valid Code is not correct");
        require(investCoinAddress == tokenAddress_, "invest Coin Not Correct!");
        require(tokenAddress_ != address(0),"Token not support Now");  
        require(tokenAmounts_ > 0,"you should deposit some coins of this token");  
        Investor storage invest = investorByAddress[msg.sender];
        require(msg.sender==invest.investorAddress,"Only the Investor can refund tokens!");
        require(invest.claimedProjectCoinAmount == 0,"Can not refund after claim coins!");
        require(invest.investedCoinAmount  >= tokenAmounts_,"your invested amount insufficient");  
        require(block.timestamp - invest.investedAt <= safeDuration * 1 minutes ,"You can only refund invest now");

        require(IERC20(tokenAddress_).approve(address(this),  tokenAmounts_), "Approve has failed"); 
        IERC20(tokenAddress_).transferFrom(address(this), invest.investorAddress, tokenAmounts_); 

        invest.investedCoinAmount -= tokenAmounts_;
        invest.investedAt = block.timestamp;
        for (uint256 i =0 ;i<investors.length;i++){
                if (investors[i].investorAddress == msg.sender)
                {
                    investors[i].investedCoinAmount -= tokenAmounts_;
                    investors[i].investedAt = block.timestamp;
                }
            }

        investedAmount -= tokenAmounts_;
        

        emit IDOEvents(block.timestamp, msg.sender, "Refund Coin");
        emit IDOStatusChange(tokenAddress_, tokenAmounts_, msg.sender, "Refund");
    }

     /*
     * *@dev the project Coin Deposit
     * 
     */
    function depositProjectCoin(address projectCoinAddress_, uint256 depositAmount) 
    payable
    public
    onlyOwner 
    {
        if(isIssued){
            require(projectCoinAddress == projectCoinAddress_, "ProjectCoinAddress Not the same as before");
        }else {
            isIssued = true;
            projectCoinAddress = projectCoinAddress_; 
        }
        IERC20(projectCoinAddress).transferFrom(msg.sender,address(this), depositAmount);  
        projectCoinAmount +=depositAmount;
       
        emit IDOEvents(block.timestamp, msg.sender, "deposit Project Coin");
        emit IDOStatusChange(projectCoinAddress, depositAmount, msg.sender, "Deposit");
    }
    /*
    *@projectCoinAddress_ the Issued Coin Contract Address 
    * @ claimAmount the Amount of ProjectCoin want to claim out
    */
    function claimProjectCoin(address projectCoinAddress_,uint256 claimAmount,string memory hashCode_) public {
        require(keccak256(abi.encodePacked(hashCode_)) ==
            keccak256(abi.encodePacked(hashCode)),"Valid Code is not correct");
        require(isIssued==true,"Token not issued!");
        Investor storage invest = investorByAddress[msg.sender];
        require(projectCoinAddress==projectCoinAddress_, "The Project Coin Address is incorrect");
        require(msg.sender==invest.investorAddress,"Only the Investor can Claim tokens!");
        require(block.timestamp-invest.investedAt > safeDuration * 1 minutes,"You can only claim invest later");
        require(invest.investedCoinAmount  * 10**decimals/ projectCoinPrice - invest.claimedProjectCoinAmount >= claimAmount,
                "your Invested Coin Amount is insufficient for claim ProjectCoin");
        require(projectCoinAmount >=  claimAmount, "Project Coin amount insufficient");

        require(IERC20(projectCoinAddress_).approve(address(this),  claimAmount), "Approve has failed"); 
        IERC20(projectCoinAddress_).transferFrom(address(this),invest.investorAddress, claimAmount);     
        
        invest.claimedProjectCoinAmount +=claimAmount;
        invest.claimedAt = block.timestamp;

        for (uint256 i =0 ;i<investors.length;i++){
                if (investors[i].investorAddress == msg.sender)
                {
                    investors[i].claimedProjectCoinAmount += claimAmount;
                    investors[i].claimedAt = block.timestamp;
                }
            }
        claimedAmount +=  claimAmount;
        projectCoinAmount -= claimAmount;

        emit IDOEvents(block.timestamp, msg.sender, "Claim");
        emit IDOStatusChange(projectCoinAddress_, claimAmount, msg.sender, "Claim");
    }

    function getInvestsByOwner(address who_)
    external
    view
    returns(Investor memory )
    {
    	Investor memory invest=investorByAddress[who_];
    	return invest;
    }
    function getInvestors()
    external
    view
    returns (Investor [] memory )
    {
        return investors;
    }
   
    /**@dev the project Coin Deposit
     * 
     * withdrawAmount w/wo decimals?
     */
    function withdrawProjectCoin(address projectCoinAddress_, uint256 withdrawAmount) 
    payable
    public
    onlyOwner 
    {
        require(isIssued = true,"Project Coin Not Issued!");
        require(projectCoinAmount >= withdrawAmount,"balance insuffcient");
        require(projectCoinAddress == projectCoinAddress_,"Project Coin Address Is Incorrect");
        projectCoinAmount -= withdrawAmount;
        uint256 platformAmount = withdrawAmount.mul(platformFee).div(feeBase);
        require(IERC20(projectCoinAddress).approve(address(this),  withdrawAmount), "Approve has failed"); 
        IERC20(projectCoinAddress).transferFrom(address(this), msg.sender, withdrawAmount.sub(platformAmount));
        IERC20(projectCoinAddress).transferFrom(address(this), platformAddress,platformAmount); 

           
        emit IDOEvents(block.timestamp, msg.sender, "withdraw Project Coin");
        emit IDOStatusChange(projectCoinAddress, withdrawAmount, msg.sender, "Deposit");
    }
    function getCoinBalance(address tokenAddress_) external view returns(uint) {
     return IERC20(tokenAddress_).balanceOf(address(this));
   }
    function getProjectInfo() external view returns( string memory,address,uint256,uint256,uint256,uint256,uint256,uint256) {
     return (name,projectCoinAddress,investTargetAmount,projectCoinPrice,investorNum,investedAmount,claimedAmount,projectCoinAmount);
   }
    /**
    **withdraw
    **/
    function totalBalance() external view returns(uint) {
      return payable(address(this)).balance;
   }
    /*
    *@projectCoinAddress_ the Issued Coin Contract Address 
    * @ claimAmount the Amount want to claim out
    */
    function withdrawInvestedCoin(address tokenAddress_,uint256 withdrawAmount) public withdrawAddressOnly {
        require(isIssued==true,"Token not issued!");
        require(investCoinAddress == tokenAddress_, "invest Coin Not Correct!");
        require( investedAmount >=withdrawAmount,"tokenAmount is insufficient");
        uint256 platformAmount = withdrawAmount.mul(platformFee).div(feeBase);
        require(IERC20(tokenAddress_).approve(address(this),  withdrawAmount), "Approve has failed"); 
        IERC20(tokenAddress_).transferFrom(address(this),msg.sender, withdrawAmount.sub(platformAmount));
        IERC20(tokenAddress_).transferFrom(address(this),platformAddress, platformAmount);     
        investedAmount -= withdrawAmount;
        emit IDOEvents(block.timestamp, msg.sender, "withDraw");
        emit IDOStatusChange(tokenAddress_, withdrawAmount, msg.sender, "withDrawINvestedCoin");
    }
    
   function withdrawAllFunds(address tokenAddress_) external withdrawAddressOnly() {
     uint256 balance = IERC20(tokenAddress_).balanceOf(address(this));
     require(investCoinAddress == tokenAddress_ || projectCoinAddress == tokenAddress_, "Coin Address Not Correct!");
     require(IERC20(tokenAddress_).approve(address(this),  balance), "Approve has failed"); 
     IERC20(tokenAddress_).transferFrom(address(this),msg.sender, balance*(feeBase-platformFee)/feeBase);
     IERC20(tokenAddress_).transferFrom(address(this),platformAddress, balance*(platformFee)/feeBase);
     if(tokenAddress_ == investCoinAddress)
        investedAmount -= balance;
     else if(tokenAddress_ == projectCoinAddress)
        projectCoinAmount -= balance;
     else 
        revert("withDraw ERROR");
      emit IDOStatusChange(tokenAddress_, balance, msg.sender, "withDrawAll");
   }

   modifier withdrawAddressOnly() {
     require(msg.sender == withdrawAddress, 'only withdrawer can call this');
     _;
   }

   function destroy() virtual public onlyOwner{
      selfdestruct(payable(msg.sender));
    }
    
}