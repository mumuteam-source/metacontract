// SPDX-License-Identifier: MIT
pragma solidity 0.8.1;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";



/**
 * @title  MetaCraftTrade
 * * @notice Implements the Trade of NFT Market. The market will be governed
 * by an ERC20 token as currency, and an ERC721 token that represents the
 * ownership of the items being traded. Only ads for selling items are
 * implemented. The item tokenization is responsibility of the ERC721 contract
 * which should encode any item details.
 */
contract MetaCraftTrade {
    using SafeMath for uint256;
    string public name;
      
    //optimize event on Jul. 5th.
    event TradeStatusChange(
       uint256 tokenID, 
	   bytes32 status,
	   address poster,
	   uint256 price,
	   string  symbol,
	   address buyer
	   );
    IERC721 itemToken;

    uint256 public platformFee = 5;
    uint256 constant feeBase = 100;
     
   address payable public withdrawAddress;
   address private owner;

    struct Trade {
        address payable poster;
        uint256 item;
        uint256 price;
        string  symbol;
        bytes32 status; // Open, Executed, Cancelled
    }

    mapping(uint256 => Trade) public trades;
    mapping(string  => address) public tokens;

    uint256 tradeCounter;

    event TradeEvents(
        uint256 timeStamp,
        address eventSender,          
        string  eventName
    );
    constructor ()
         
    {
        
	name = "MetaCraftTrade";
	owner = msg.sender;
    }
    
    function setItemToken(address itemTokenAddress_) external {
        require(msg.sender==owner,"Only Owner Function!");
        itemToken = IERC721(itemTokenAddress_);
        emit TradeEvents(block.timestamp,msg.sender,"setItemToken");
    }
    
    function setWithDraw (address withDrawTo_) external{
        require(msg.sender==owner,"Only Owner Function!");
        withdrawAddress = payable(withDrawTo_);
        emit TradeEvents(block.timestamp,msg.sender,"setWithDraw");
    }

     function setPlatformFee (uint256 platformFee_) external{
        require(msg.sender==owner,"Only Owner Function!");
        platformFee = platformFee_;
        emit TradeEvents(block.timestamp,msg.sender,"setPlatformFee");
    }
    
     /**  
    *@dev add address of token to list of supported tokens using 
    * token symbol as identifier in mapping 
    */  
    function addNewToken(string memory symbol_, address address_) 
    public  
    returns (bool) 
    {  
      require(msg.sender == owner,"Only the owner of this Contract could do It!");
      tokens[symbol_] = address_;  
      emit TradeEvents(block.timestamp,msg.sender,"addNewToken");
      return true;  
    } 
     /**  
     * @dev update address of token we changed
     */  
    function updateToken(string memory symbol_,address address_) public returns (bool) {  
      require(msg.sender == owner,"Only the owner of this Contract could do It!");
      require(tokens[symbol_] != address(0));  
      tokens[symbol_] = address_; 
      emit TradeEvents(block.timestamp,msg.sender,"updateToken"); 
      return true;  
    }  
    /**  
     * @dev remove address of token we no more support 
     */  
    function removeToken(string memory symbol_) public returns (bool) {  
      require(msg.sender == owner,"Only the owner of this Contract could do It!");
      require(tokens[symbol_] != address(0));  
      delete(tokens[symbol_]); 
      emit TradeEvents(block.timestamp,msg.sender,"removeToken"); 
      return true;  
    }  
    
    /**
     * @dev Returns the details for a trade.
     * @param _item The id for the item trade.
     */
    function getTrade(uint256 _item)
        public
        virtual
        view
        returns(address, uint256, uint256, string memory, bytes32)
    {
        Trade memory trade = trades[_item];
        return (trade.poster, trade.item, trade.price, trade.symbol, trade.status);
    }

    /**
     * @dev Opens a new trade. Puts _item in escrow.
     * @param _item The id for the item to trade.
     * @param _price The amount of currency for which to trade the item.
     */
    function openTrade(string memory _symbol,uint256 _item, uint256 _price)
        public
        virtual
	    payable
    {
        itemToken.transferFrom(msg.sender, address(this), _item);
        trades[_item] = Trade({
            poster: payable(msg.sender),
            item: _item,
            price: _price,
            symbol:_symbol,
            status: "Open"
        });
        //tradeCounter += 1;
        emit TradeStatusChange(_item, "Open",msg.sender,_price,_symbol,address(this));
	
    }

    /**
     * @dev Executes a trade. Must have approved this contract to transfer the
     * amount of currency specified to the poster. Transfers ownership of the
     * item to the filler.
     * @param _item The id of an existing item
     */
    function executeTrade(uint256 _item)
        public
        virtual
	payable
    {
        Trade memory trade = trades[_item];
        require(trade.status == "Open", "Trade is not Open.");
	    require(msg.value>= trade.price,"Can't Lower than Sell Price");
        require(msg.sender != trade.poster,"Owner can't buy");
        itemToken.transferFrom(address(this), msg.sender, trade.item);
	uint256 perf = (msg.value).mul(platformFee).div(feeBase);
	//payable(withdrawAddress).transfer(perf);
    Address.sendValue(payable(withdrawAddress),perf);
	//payable(trade.poster).transfer(msg.value-perf);
    Address.sendValue(payable(trade.poster),msg.value.sub(perf));


        trades[_item].status = "Executed";
        emit TradeStatusChange(_item, "Executed",trade.poster,msg.value,trade.symbol, msg.sender);
    }
    
    /**
     * @dev Executes a trade. Must have approved this contract to transfer the
     * amount of currency specified to the poster. Transfers ownership of the
     * item to the filler.
     * @param _item The id of an existing item
     */
    function executeTrade(string memory symbol_,uint256 price_, uint256 _item)
        public
        virtual
    {
        Trade memory trade = trades[_item];
        require(trade.status == "Open", "Trade is not Open.");
	    require(price_>= trade.price,"Can't Lower than Sell Price");
        require(msg.sender != trade.poster,"Owner can't buy");
        require(keccak256(abi.encodePacked(symbol_)) == 
                keccak256(abi.encodePacked(trade.symbol)),"Symbol is not correct");
        itemToken.transferFrom(address(this), msg.sender, trade.item);
    	uint256 perf =(price_).mul(platformFee).div(feeBase);
        require(IERC20(tokens[symbol_]).approve(trade.poster,  price_.sub(perf)), "Approve has failed"); 
    	IERC20(tokens[symbol_]).transferFrom(msg.sender, trade.poster, price_.sub(perf));
    	require(IERC20(tokens[symbol_]).approve(withdrawAddress,  perf), "Approve has failed"); 
    	IERC20(tokens[symbol_]).transferFrom(msg.sender, withdrawAddress, perf);

        trades[_item].status = "Executed";
        emit TradeStatusChange(_item, "Executed",trade.poster,price_,symbol_,msg.sender);
    }

    /**
     * @dev Cancels a trade by the poster.
     * @param _item The trade to be cancelled.
     */
    function cancelTrade(uint256 _item)
        public
        virtual
	payable
    {
        Trade memory trade = trades[_item];
        require(
            msg.sender == trade.poster,
            "Trade can be cancelled only by poster."
        );
        require(trade.status == "Open", "Trade is not Open.");
        itemToken.transferFrom(address(this), trade.poster, trade.item);
        trades[_item].status = "Cancelled";
        emit TradeStatusChange(_item, "Cancelled", address(this),0,trade.symbol,msg.sender);
    }

    /**
    **withdraw
    **
    **
    **/
    function totalBalance() external view returns(uint) {
     //return currencyToken.balanceOf(address(this));
      return payable(address(this)).balance;
   }

   function withdrawFunds() external withdrawAddressOnly() {
     //currencyToken.transferFrom(address(this),msg.sender, currencyToken.balanceOf(address(this)));
      // payable(msg.sender).transfer(this.totalBalance());
      Address.sendValue(payable(msg.sender),this.totalBalance());
       emit TradeEvents(block.timestamp,msg.sender,"withdrawFunds");
   }
    
    function withdrawFunds(string memory symbol_) external withdrawAddressOnly() {
     require(IERC20(tokens[symbol_]).approve(address(this), IERC20(tokens[symbol_]).balanceOf(address(this))), "Approve has failed"); 
     IERC20(tokens[symbol_]).transferFrom(address(this),msg.sender, IERC20(tokens[symbol_]).balanceOf(address(this)));
       //payable(msg.sender).transfer(this.totalBalance());
    emit TradeEvents(block.timestamp,msg.sender,"withdrawFunds");
   }
   modifier withdrawAddressOnly() {
     require(msg.sender == withdrawAddress, 'only withdrawer can call this');
   _;
   }

   function destroy() virtual public {
	require(msg.sender == owner,"Only the owner of this Contract could destroy It!");
        if (msg.sender == owner) selfdestruct(payable(owner));
        
        
          
        emit TradeEvents(block.timestamp,msg.sender,"destory");
    }
   
   
}