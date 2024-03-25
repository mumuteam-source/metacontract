// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


/**
 * @title MetaCraftIDO
 *
 */

contract MetaCraftIDO is Ownable (msg.sender), ReentrancyGuard {
    
    using SafeERC20 for IERC20;
    string public name;
    address payable public withdrawAddress;
    address public projectCoinAddress;//raisecoinaddress
    address public investCoinAddress; //moneyaddress
    uint256 public investTargetAmount;  //BUSD or USDT target Amount;
    uint256 public projectCoinPrice=1e16; //0.01; price
    uint256 public startTimestamp = 1711035000;
    uint256 public endSellTimestamp = 1711040000;
    uint256 public protectTimestamp = 1711045000;
    uint256 public claimTimestamp = 1711050000;

    Investor []  public investors;  //participants investors.length;
    uint256 public decimals=18;
    //bool public isIssued = false;
  
    
    
    uint public raiseStatus=0; // 0-Not begin; 1-isSelling;2-isWatting; 3- isProtecting; 4- isClaiming;
    
   
    address public publicKey = address(0xEe8b45a0c599e8E6512297f99687BF5FE3359147);
    mapping(address=>uint256) public investedAmount;  //user Invested Amount of raise Coin /USDT or BUSD
    mapping(address=>uint256) public claimedAmount;  // User Claimed Amount of Project Coin
    mapping(address=>uint256) public refundedAmount; //user Refunded Amount of raise Coin
    mapping(address=>uint256) public projectCoinAmount; // IDO Project Coin Amount
    //VIP level logicals:
    //[tokenAddress][userLevel--1,2,3,4]==>uint256 amount
    mapping(address=>mapping(uint8 =>uint256)) public VIPAmount;
    //VIPLimit[userLevel]==>limit
    mapping(uint8=>uint256) public VIPLimit;
    // VIPPerLimit[userLevel] => Limit Percent of userLevel
    mapping(uint8=>uint256) public VIPPerLimit;
    // userVIPAmount[useraddress][tokenAddress][1] ==> user amount of VIP useraddress
    mapping(address=>mapping(address=>mapping(uint8 =>uint256))) public userVIPAmount;
           
    struct Investor {
        address investCoinAddress; //usdt or BUSD contract address;
        address payable investorAddress;
        uint256 investedCoinAmount;  // user invest USDT or BUSD amount
        uint256 refundedCoinAmount;  // user Refund USDT or BUSD amount from IDO
        uint256 claimedProjectCoinAmount; //projectCoin Amount
        uint256 investedAt;
        uint256 refundedAt;
        uint256 claimedAt;
    }
 
    struct projectInfoGet {
        uint256 price;
        uint256 targetAmount;
        uint256 currentAmount;
        uint256 participants;
        address raiseCoinAddress;
        address moneyAddress;
        uint256 vip1Allocation;
        uint256 vip2Allocation;
        uint256 vip3Allocation;
        uint256 vip1Percent;
        uint256 vip2Percent;
        uint256 vip3Percent;
        uint256 startTime;
        uint256 endSellTime;
        uint256 protectTime;
        uint256 claimTime;
        uint raiseStatus;
        uint256 vip1CurrentAmount;
        uint256 vip2CurrentAmount;
        uint256 vip3CurrentAmount;
    }

    struct projectInfoSet {
        uint256 price;
        uint256 targetAmount;
        address raiseCoinAddress;
        address moneyAddress;
        uint256 vip1Allocation;
        uint256 vip2Allocation;
        uint256 vip3Allocation;
        uint256 vip1Percent;
        uint256 vip2Percent;
        uint256 vip3Percent;
        uint256 startTime;
        uint256 endSellTime;
        uint256 protectTime;
        uint256 claimTime;
        uint raiseStatus;
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

    constructor (string memory projectName, 
    uint256 targetAmount_, 
    address investCoinAddress_, 
    address publicKey_)
    {
       	name = projectName;
        investTargetAmount = targetAmount_ * 10 ** decimals;
        
        withdrawAddress = payable(msg.sender);

        investCoinAddress = investCoinAddress_;
        publicKey = publicKey_;
        
        VIPLimit[1] = 100;
        VIPLimit[2] = 500;
        VIPLimit[3] = 1000;

        VIPPerLimit[1] = 20;
        VIPPerLimit[2] = 30;
        VIPPerLimit[3] = 50;

    }
    
    function setWithdrawAddress (address withDrawTo_) external onlyOwner{
        withdrawAddress = payable(withDrawTo_);
        emit IDOEvents(block.timestamp, msg.sender, "SetWithDrawAddress");
    }

    function setTimestamps (uint256 startTime_,uint256 endSellTime_,
                            uint256 protectTime_, uint256 claimTime_)
                public
                onlyOwner
                {
                    startTimestamp = startTime_;
                    endSellTimestamp = endSellTime_;
                    protectTimestamp = protectTime_;
                    claimTimestamp = claimTime_;
                    emit IDOEvents(block.timestamp, msg.sender, "setTimeStamps");
                }


    function setProjectCoinAddress (address projectCoinAddress_)
    public 
    onlyOwner
    {
        projectCoinAddress = projectCoinAddress_;
        emit IDOEvents(block.timestamp, msg.sender, "set projectCoinAddress");
    }
    

    function  setParameters (string memory  _projectName,
                             address _investCoinAddress,
                             address _publicKey,
                             uint256 _projectCoinPrice,
                             uint _raiseStatus)
    public 
    onlyOwner
    {
       	name = _projectName;
        investCoinAddress = _investCoinAddress;
        publicKey = _publicKey;
        projectCoinPrice = _projectCoinPrice;
        raiseStatus = _raiseStatus;
        emit IDOEvents(block.timestamp, msg.sender, "set Parameters");
    }


    function getProjectInfo (address _tokenAddress)
    public 
    view 
    returns ( projectInfoGet memory )
    {
        uint256 currentStatus = 0;
        if (block.timestamp < startTimestamp) currentStatus = 0;
        else if (block.timestamp < endSellTimestamp) currentStatus = 1;
        else if (block.timestamp < protectTimestamp) currentStatus = 2;
        else if (block.timestamp < claimTimestamp) currentStatus = 3;
        else  currentStatus = 4;

        projectInfoGet memory getInfo = 
            projectInfoGet({
                 price:projectCoinPrice,
                 targetAmount:investTargetAmount,
                 currentAmount:investedAmount[_tokenAddress],
                 participants:investors.length,
                 raiseCoinAddress:projectCoinAddress,
                 moneyAddress:investCoinAddress,
                 vip1Allocation:VIPLimit[1],
                 vip2Allocation:VIPLimit[2],
                 vip3Allocation:VIPLimit[3],
                 vip1Percent:VIPPerLimit[1],
                 vip2Percent:VIPPerLimit[2],
                 vip3Percent:VIPPerLimit[3],
                 raiseStatus:currentStatus,
                 startTime:startTimestamp,
                 endSellTime:endSellTimestamp,
                 protectTime:protectTimestamp,
                 claimTime: claimTimestamp,
                 vip1CurrentAmount: VIPAmount[_tokenAddress][1],
                 vip2CurrentAmount: VIPAmount[_tokenAddress][2],
                 vip3CurrentAmount: VIPAmount[_tokenAddress][3]

            });
        return getInfo;
    }

    function getVIPAmount(address tokenAddress_)
    public 
    view
    returns (uint256,uint256,uint256,uint256)
    {
        return(VIPAmount[tokenAddress_][1],VIPAmount[tokenAddress_][2],VIPAmount[tokenAddress_][3],VIPAmount[tokenAddress_][4]);
    }

    function getUserVIPAmount(address tokenAddress_, address userAddress_)
    public 
    view
    returns (uint256,uint256,uint256,uint256)
    {
        return(userVIPAmount[userAddress_][tokenAddress_][1],
               userVIPAmount[userAddress_][tokenAddress_][2],
               userVIPAmount[userAddress_][tokenAddress_][3],
               userVIPAmount[userAddress_][tokenAddress_][4]);
    }
    function setProjectInfo ( 
        uint256 timestamp,
        bytes32 nonce, 
        uint8 userLevel,
        bytes32 message,
        bytes memory signature,
        projectInfoSet calldata info)
    public 
    nonReentrant 
    notContract(msg.sender) 
    {
                require(block.timestamp < startTimestamp,"Can not set parameters after project start");
                bytes32 challenge = getChallenge(timestamp, nonce,userLevel, msg.sender);
                require(message == challenge,"message not correct!");
                bool isVerified = verified(publicKey,challenge, signature);
                require(isVerified, "Verify Error!");

                projectCoinPrice=info.price;
                investTargetAmount = info.targetAmount;
                projectCoinAddress=info.raiseCoinAddress;
                investCoinAddress=info.moneyAddress;
                VIPLimit[1]=info.vip1Allocation;
                VIPLimit[2]=info.vip2Allocation;
                VIPLimit[3]=info.vip3Allocation;
                VIPPerLimit[1] = info.vip1Percent;
                VIPPerLimit[2]= info.vip2Percent;
                VIPPerLimit[3] = info.vip3Percent;
                raiseStatus=info.raiseStatus;
                startTimestamp = info.startTime;
                endSellTimestamp = info.endSellTime;
                protectTimestamp = info.protectTime;  
                claimTimestamp = info.claimTime;  
    }


    //invest with sign
    function investInWithVerify(
        uint256 timestamp,
        bytes32 nonce, 
        uint8 userLevel,
        bytes32 message,
        bytes memory signature,
        address _tokenAddress, 
        uint256 tokenAmounts_
        )
        nonReentrant 
        notContract(msg.sender) 
        public  
        {
            bytes32 challenge = getChallenge(timestamp, nonce,userLevel, msg.sender);
            require(message == challenge,"message not correct!");
            bool isVerified = verified(publicKey,challenge, signature);
            require(isVerified, "Verify Error!");
            require(investCoinAddress == _tokenAddress, "invest Coin Not Correct!");
            require(userLevel == 1 || userLevel ==2 || userLevel ==3, "User Level Error!");
            require(block.timestamp >= startTimestamp && block.timestamp <endSellTimestamp, "you should invest after the IDO is in Selling ");
            require(_tokenAddress != address(0),"Token not support Now");  
            require(tokenAmounts_ > 0,"you should deposit some coins of this token");  
            
            require(tokenAmounts_ % projectCoinPrice ==0, "invest amount should be an integral dividen by the token Price"); 


            Investor storage investor = investorByAddress [msg.sender];
            
            
            require(investor.investedCoinAmount + tokenAmounts_ <= VIPLimit[userLevel] * 10 ** decimals,"Level Limit Over Flow ");
            require((VIPAmount[_tokenAddress][userLevel]+ tokenAmounts_)*100/investTargetAmount <= VIPPerLimit[userLevel], "Level Percent Limit Over Flow!");
            
            if(investor.investorAddress == msg.sender){
                require(investor.investCoinAddress == _tokenAddress, "The Coin Address incorrect!");
                require(investor.claimedProjectCoinAmount == 0,"Can not invest after claimed coins!");

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
            }
            
            investedAmount[_tokenAddress] += tokenAmounts_;
            VIPAmount[_tokenAddress][userLevel]+=tokenAmounts_;
            userVIPAmount[msg.sender][_tokenAddress][userLevel]+=tokenAmounts_;

            IERC20(_tokenAddress).safeTransferFrom(msg.sender,address(this), tokenAmounts_);  
            emit IDOEvents(block.timestamp, msg.sender, "invest Coin");
            emit IDOStatusChange(_tokenAddress, tokenAmounts_, msg.sender, string(abi.encodePacked("Invest ",userLevel)));
            
        }
    //get Challenge
    function getChallenge(uint256 timestamp,
                              bytes32 nonce, 
                              uint8 userLevel,
                              address userAddress
                             ) private pure returns (bytes32){
        bytes32 challenge = keccak256(abi.encodePacked( userAddress, timestamp, nonce, userLevel));
       
        return challenge;   
    }
    

    function verified(
        address signer,
        bytes32 message,
        bytes memory signature
    ) private pure returns (bool)
    {
        
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(message);
        address recovered = ecrecover(ethSignedMessageHash, v, r, s);
        return recovered == signer;
    }

    function getEthSignedMessageHash(bytes32 _messageHash) private  pure returns (bytes32) {
      
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    function splitSignature(bytes memory sig)
    internal
    pure
    returns (bytes32 r, bytes32 s, uint8 v)
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))   
            v := byte(0, mload(add(sig, 96)))
        }

        if (v < 27) {
            v += 27;
        }
    }

    function refundOut(
        uint256 timestamp,
        bytes32 nonce, 
        uint8 userLevel,
        bytes32 message,
        bytes memory signature,
        address tokenAddress_) 
        nonReentrant 
        notContract(msg.sender) 
        public {
        
        bytes32 challenge = getChallenge(timestamp, nonce,userLevel, msg.sender);
        require(message == challenge,"message not correct!");
        bool isVerified = verified(publicKey,challenge, signature);
        require(isVerified, "Verify Error!");

        require(investCoinAddress == tokenAddress_, "invest Coin Not Correct!");
        require(tokenAddress_ != address(0),"Token not support Now");  
       
        Investor storage invest = investorByAddress[msg.sender];

        require(msg.sender==invest.investorAddress,"Only the Investor can refund tokens!");
        require(invest.claimedProjectCoinAmount == 0,"Can not refund after claim coins!");

        
        require(block.timestamp >= protectTimestamp && block.timestamp < claimTimestamp, "you should refund after the IDO is in protect ");
        

        IERC20(tokenAddress_).safeTransfer(invest.investorAddress, invest.investedCoinAmount); 

        investedAmount[tokenAddress_] -= invest.investedCoinAmount;
        refundedAmount[tokenAddress_] += invest.investedCoinAmount;

        for (uint256 i =0 ;i<investors.length;i++){
                if (investors[i].investorAddress == msg.sender)
                {
                    investors[i].investedCoinAmount =0;
                    investors[i].refundedCoinAmount = invest.investedCoinAmount;
                    investors[i].refundedAt = block.timestamp;
                }
            }
        
       
        //VIPAmount[tokenAddress_][userLevel] -= invest.investedCoinAmount;
        require(userVIPAmount[msg.sender][tokenAddress_][1]+userVIPAmount[msg.sender][tokenAddress_][2]+userVIPAmount[msg.sender][tokenAddress_][3]
                == invest.investedCoinAmount, "User VIP Amount Error!");

        VIPAmount[tokenAddress_][1] -= userVIPAmount[msg.sender][tokenAddress_][1];
        VIPAmount[tokenAddress_][2] -= userVIPAmount[msg.sender][tokenAddress_][2];
        VIPAmount[tokenAddress_][3] -= userVIPAmount[msg.sender][tokenAddress_][3];

        userVIPAmount[msg.sender][tokenAddress_][1] = 0;
        userVIPAmount[msg.sender][tokenAddress_][2] = 0;
        userVIPAmount[msg.sender][tokenAddress_][3] = 0;
        
        invest.refundedCoinAmount = invest.investedCoinAmount;
        invest.investedCoinAmount = 0;
        invest.refundedAt = block.timestamp; 

        emit IDOEvents(block.timestamp, msg.sender, "Refund Coin");
        emit IDOStatusChange(tokenAddress_, invest.investedCoinAmount, msg.sender, string(abi.encodePacked("Refund ",userLevel)));
    }

     /*
     * *@dev the project Coin Deposit
     * 
     */
    function depositProjectCoin(
        uint256 timestamp,
        bytes32 nonce, 
        uint8 userLevel,
        bytes32 message,
        bytes memory signature,
        address projectCoinAddress_, uint256 depositAmount) 
    payable
    public
    //onlyOwner 
    {
        
        bytes32 challenge = getChallenge(timestamp, nonce,userLevel, msg.sender);
        require(message == challenge,"message not correct!");
        bool isVerified = verified(publicKey,challenge, signature);
        require(isVerified, "Verify Error!");


        
        require(projectCoinAddress == projectCoinAddress_, "ProjectCoinAddress Not the same as before");
       
        IERC20(projectCoinAddress).safeTransferFrom(msg.sender,address(this), depositAmount);  

        projectCoinAmount[projectCoinAddress_] = IERC20(projectCoinAddress_).balanceOf(address(this));
       
        emit IDOEvents(block.timestamp, msg.sender, "deposit Project Coin");
        emit IDOStatusChange(projectCoinAddress, depositAmount, msg.sender, string(abi.encodePacked("Deposit ",userLevel)));
    }

    function getProjectCoinAmount (address projectCoinAddress_)
    public 
    view 
    returns (uint256)
    {
       return  IERC20(projectCoinAddress_).balanceOf(address(this));
    }
    /*
    * @projectCoinAddress_ the Issued Coin Contract Address 
    * @ claimAmount the Amount of ProjectCoin want to claim out
    */
    function claimProjectCoin(
        uint256 timestamp,
        bytes32 nonce, 
        uint8 userLevel,
        bytes32 message,
        bytes memory signature,
        address projectCoinAddress_) 
        nonReentrant 
        notContract(msg.sender) 
        public {
        
        bytes32 challenge = getChallenge(timestamp, nonce,userLevel, msg.sender);
        require(message == challenge,"message not correct!");
        bool isVerified = verified(publicKey,challenge, signature);
        require(isVerified, "Verify Error!");

        // require(isIssued==true,"Token not issued!");
        Investor storage invest = investorByAddress[msg.sender];

        require(projectCoinAddress==projectCoinAddress_, "The Project Coin Address is incorrect");
        require(msg.sender==invest.investorAddress,"Only the Investor can Claim tokens!");
        //require(raiseStatus == 3 || raiseStatus == 4,"You can only Claim during the Protected or Claim status");
        require(block.timestamp >= protectTimestamp, "you should refund after the IDO is in protect ");
        require(invest.claimedProjectCoinAmount == 0, "You had already Claimed out!");
        uint256 claimAmount = invest.investedCoinAmount * 10 ** decimals / projectCoinPrice ; 
        require(IERC20(projectCoinAddress_).balanceOf(address(this))>=  claimAmount, "Project Coin amount insufficient");

        //require(IERC20(projectCoinAddress_).approve(address(this),  claimAmount), "Approve has failed"); 
        IERC20(projectCoinAddress_).safeTransfer(invest.investorAddress, claimAmount);     
        
        invest.claimedProjectCoinAmount +=claimAmount;
        invest.claimedAt = block.timestamp;

        for (uint256 i =0 ;i<investors.length;i++){
                if (investors[i].investorAddress == msg.sender)
                {
                    investors[i].claimedProjectCoinAmount += claimAmount;
                    investors[i].claimedAt = block.timestamp;
                }
            }
        claimedAmount[projectCoinAddress_] +=  claimAmount;
        projectCoinAmount[projectCoinAddress_] = IERC20(projectCoinAddress_).balanceOf(address(this));

        emit IDOEvents(block.timestamp, msg.sender, "Claim");
        emit IDOStatusChange(projectCoinAddress_, claimAmount, msg.sender,  string(abi.encodePacked("Claim ",userLevel))); 
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

    function getCurrentAmounts(address tokenAddress_, address projectCoinAddress_)
    external 
    view 
    returns (uint256, uint256, uint256,uint256){
        return (investedAmount[tokenAddress_],refundedAmount[tokenAddress_],claimedAmount[projectCoinAddress_], investTargetAmount);
    }
    
    function getCoinBalance(address tokenAddress_) external view returns(uint) {
     return IERC20(tokenAddress_).balanceOf(address(this));
    }

    function getsProjectInfo(address _tokenAddress,address projectCoinAddress_) 
     external 
     view 
     returns( string memory,address,uint256,uint256,uint256,uint256,uint256) {

     return (name,projectCoinAddress,projectCoinPrice,
             investedAmount[_tokenAddress],
             refundedAmount[_tokenAddress],
             claimedAmount[projectCoinAddress_],
             IERC20(projectCoinAddress_).balanceOf(address(this)));
   }
   /**
    ** withdraw projectCoin or investCoin by manager;
    **/
      
   function withdrawAllFunds(address tokenAddress_) 
    external
    nonReentrant 
    notContract(msg.sender) 
    withdrawAddressOnly() {
     uint256 balance = IERC20(tokenAddress_).balanceOf(address(this));
     require(investCoinAddress == tokenAddress_ || projectCoinAddress == tokenAddress_, "Coin Address Not Correct!");
     
     IERC20(tokenAddress_).safeTransfer(msg.sender, balance);

     if(tokenAddress_ == investCoinAddress){
        investedAmount[tokenAddress_] -= balance;
        refundedAmount[tokenAddress_] += balance;
        emit IDOStatusChange(tokenAddress_, balance, msg.sender, "Manager Withdraw invest Coins");
        }
     else if(tokenAddress_ == projectCoinAddress){

        projectCoinAmount[tokenAddress_] = IERC20(tokenAddress_).balanceOf(address(this));
        claimedAmount[tokenAddress_] += balance;
        emit IDOStatusChange(tokenAddress_, balance, msg.sender, "Manager Withdraw invest Coins");
        }
     else 
        revert("withDraw TokenAddress ERROR");
     
   }

   modifier withdrawAddressOnly() {
     require(msg.sender == withdrawAddress, 'only withdrawer can call this');
     _;
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
}