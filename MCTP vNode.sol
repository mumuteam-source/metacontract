// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";    
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

contract MetaCraftVNode is ERC721{
    // ERC20 token used for minting NFT
    IERC20 public ERC20Token;
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    address private owner;
    // Base URI
    string private _baseURIextended;
    // Mapping to track minted addresses
    mapping(address => bool) public _mintedAddresses;

    // Price in ERC20 tokens to mint NFT
    uint256 public mintPrice;
    bool public locked = true;

    uint256 public currentMaxNodes = 500;
    
      // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;
    // address's parent
    mapping (address=>address) public parent;
    // tokenOwner
    mapping (uint256=>address) public tokenOwner;
    mapping (address => NodeInfo) public nodes;
    address payable  public feeAddress = payable(address(0x498d09597e35f00ECaB97f5A10F6369aDde00364));
    // Event emitted when an NFT is minted

    event NodeStatusChange(address owner, address parent, uint256  tokenId, string status, uint256 timestamp);
    event TransactionCreated(address withdrawAddress,  uint256 timestamp, uint256 transactionId);
    event TransactionCompleted(address withdrawAddress,  uint256 timestamp, uint256 transactionId);
    event TransactionSigned(address by, uint transactionId);
    event NodeEvents(
        uint256 timeStamp,
        address eventSender,          
        string  eventName
    );
    event TransactionReadyForExecution(
        address itemToken,
        uint256 timestamp,
        uint transactionId
    );

    struct Transaction {
      address withdrawAddress_;
      uint8 signatureCount;
      uint256 readyForExecutionTimestamp; 
      uint256 timestamp;
    }
    struct TokenInfo {
        uint256 tokenId;
        address tokenOwner;
        uint256 tokenPrice;
        uint256 mintTimestamp;
    }
    struct NodeInfo {
        address nodeAddress;
        address nodeParent;
        TokenInfo tokenInfo;
    }

    mapping(address => uint8) private _owners;
    mapping ( uint=>mapping(address => uint8)) signatures;
    mapping (uint => Transaction) private _transactions;
    uint[] private _pendingTransactions;
    uint256 public observationPeriod = 24 hours;
    uint256 public maxPendingTime = 96 hours;

    mapping (uint => TxAddOwner) private _txaddowners;
    mapping (uint => TxDelOwner) private _txdelowners;

    struct TxAddOwner {
      address owner;
      uint8 signatureCount;
      uint256 timestamp;
    }

     struct TxDelOwner {
      address owner;
      uint8 signatureCount;
      uint256 timestamp;
    }

    uint constant MIN_SIGNATURES = 3;
    uint private _transactionIdx;

    constructor(
        string memory _name,
        string memory _symbol,
        address _erc20Token,
        uint256 _mintPrice
    ) ERC721(_name, _symbol) {
        ERC20Token = IERC20(_erc20Token);
        mintPrice = _mintPrice * 10 ** 18;
        owner = msg.sender;

       _owners[address(0xce44C139234E2E8146c82eF42dC3d9fc39833361)] = 1;
       _owners[address(0xd0c06ced3DFaA617c105166BB5cADc317DaaA41B)] = 1;
       _owners[address(0xa1813Fb2A6882E8248CD4d4C789480F50CAf7ca4)] = 1;
    }
     modifier validOwner() {
        require(_owners[msg.sender] == 1, "not Authorized Mulsig User !");
        _;
    }

    function  deleteMaxPendingTx()

    private 
    {
         require(_pendingTransactions.length <= 1,"has pending txs! Please sign them first");   
         
         if(_pendingTransactions.length == 1 ){
                uint txId = _pendingTransactions[0];
                Transaction storage pendingwithdrawTx = _transactions[txId];
                TxAddOwner storage pendingaddTx = _txaddowners[txId];
                TxDelOwner storage pendingdelTx = _txdelowners[txId];
                //for withdraw Txs
                if (pendingwithdrawTx.timestamp > 0 ){
                    if(block.timestamp - pendingwithdrawTx.timestamp > maxPendingTime){
                         deleteTransaction(txId);
                    } else revert("has pending txs yet! Please sign them first");
                   
                }
                //for add user Txs
                if (pendingaddTx.timestamp> 0 ){
                    if(block.timestamp - pendingaddTx.timestamp > maxPendingTime) {
                         deleteAddUserTx(txId);
                    }else revert("has pending txs yet! Please sign them first");
                   
                } 
                //for del user Txs
                if (pendingdelTx.timestamp > 0 ){
                    if (block.timestamp - pendingdelTx.timestamp > maxPendingTime){
                        deleteDelUserTx(txId);
                    }else revert("has pending txs yet! Please sign them first");
                    
                }

            }
    }

    function addOwner(address _owner)
        public 
        {
            require(msg.sender==owner,"Only owner can set Parameters");
            require(_owner != address(0),"Zero Address Error!");
            deleteMaxPendingTx();

           
            uint256 transactionId = _transactionIdx++;
            TxAddOwner memory txOwner;
            
            txOwner.owner = _owner;
            txOwner.timestamp = block.timestamp;
            txOwner.signatureCount = 0;
            _txaddowners[transactionId]=txOwner;
            _pendingTransactions.push(transactionId);

            emit TransactionCreated(_owner,  block.timestamp, transactionId);
            emit NodeEvents(block.timestamp,msg.sender, "AddValieOwner");
    }

    function removeOwner(address _owner)
        public {
            require(msg.sender==owner,"Only owner can set Parameters");
            require(_owner != address(0),"Zero Address Error!");
            deleteMaxPendingTx();

            uint256 transactionId = _transactionIdx++;
            TxDelOwner memory txOwner;
            
            txOwner.owner = _owner;
            txOwner.timestamp = block.timestamp;
            txOwner.signatureCount = 0;
            _txdelowners[transactionId]=txOwner;
            _pendingTransactions.push(transactionId);
           
            emit TransactionCreated(_owner,  block.timestamp, transactionId);
            emit NodeEvents(block.timestamp,msg.sender, "RemoveValieOwner");
    }
    
    function signUserAdd(uint transactionId)
      validOwner
      public {

            TxAddOwner storage transaction = _txaddowners[transactionId];

            // Transaction must exist
            require(address(0) != transaction.owner,  "Fee To Zero Addresses!");
            // Creator cannot sign the transaction
            require(msg.sender !=transaction.owner , "Can't Sign Self!" );
            // Cannot sign a transaction more than once
            require(signatures[transactionId][msg.sender] != 1, "Can't Sign Again with the same Account!");
            signatures[transactionId][msg.sender] = 1;

            transaction.signatureCount++;
            transaction.timestamp= block.timestamp;

            emit TransactionSigned(msg.sender, transactionId);
           
            if (transaction.signatureCount >= MIN_SIGNATURES) {
                    _owners[(transaction.owner)]=1;
                    emit TransactionCompleted(transaction.owner, block.timestamp, transactionId);
                    deleteAddUserTx(transactionId);
            }
    }
    function deleteAddUserTx(uint transactionId)
        
        private {
            TxAddOwner memory transaction = _txaddowners[transactionId];
            require(transaction.timestamp > 0, "transaction not exist!");
           
            uint256 txLength = _pendingTransactions.length;
            for (uint256 i = 0; i < txLength; i++) {
                if (_pendingTransactions[i] == transactionId) {
                    
                    _pendingTransactions[i] = _pendingTransactions[txLength - 1];
                   
                    _pendingTransactions.pop();
                    break;
                }
            }
            delete _txaddowners[transactionId];
    }
    function signUserDel(uint transactionId)
      validOwner
      public {

            TxDelOwner storage transaction = _txdelowners[transactionId];

            // Transaction must exist
            require(address(0) != transaction.owner,  "Fee To Zero Addresses!");
            // Creator cannot sign the transaction
            require(msg.sender !=transaction.owner , "Can't Sign Self!" );
            // Cannot sign a transaction more than once
            require(signatures[transactionId][msg.sender] != 1, "Can't Sign Again with the same Account!");
          
            signatures[transactionId][msg.sender] = 1;

            transaction.signatureCount++;
            transaction.timestamp= block.timestamp;

            emit TransactionSigned(msg.sender, transactionId);
           
            if (transaction.signatureCount >= MIN_SIGNATURES) {
                    _owners[transaction.owner]=0;
                
                    emit TransactionCompleted(transaction.owner, block.timestamp, transactionId);
                    deleteDelUserTx(transactionId);
            }
    }
   function deleteDelUserTx(uint transactionId)
        
        private {
            TxDelOwner memory transaction = _txdelowners[transactionId];
            require(transaction.timestamp > 0, "transaction not exist!");
           
            uint256 txLength = _pendingTransactions.length;
            for (uint256 i = 0; i < txLength; i++) {
                if (_pendingTransactions[i] == transactionId) {
                    
                    _pendingTransactions[i] = _pendingTransactions[txLength - 1];
                   
                    _pendingTransactions.pop();
                    break;
                }
            }
            delete _txdelowners[transactionId];
    }

    function getPendingTransactions()
      view
      public
      returns (uint[] memory) {
      return _pendingTransactions;
    }
    function getPendingTransaction(uint transactionId)
      view
      public
      returns (Transaction memory, TxAddOwner memory, TxDelOwner memory) {
        Transaction storage pendingwithdrawTx = _transactions[transactionId];
        TxAddOwner storage pendingaddTx = _txaddowners[transactionId];
        TxDelOwner storage pendingdelTx = _txdelowners[transactionId];

      return (pendingwithdrawTx,pendingaddTx,pendingdelTx);
    }
    function  getValidOwner(address _owner)  view public returns (uint){
       
        return _owners[_owner];
    }
     function signTransaction(uint transactionId) 
     validOwner 
     public {
        Transaction storage transaction = _transactions[transactionId];
       
        require(address(0) != transaction.withdrawAddress_,  "Fee To Zero Addresses!");
        // Creator cannot sign the transaction
        require(msg.sender !=transaction.withdrawAddress_ , "Can't Sign Self!" );
        // Cannot sign a transaction more than once
        require(signatures[transactionId][msg.sender] != 1, "Can't Sign Again with the same Account!");
        // no more than MIN_SIGNATURES Signs
        require(transaction.signatureCount < MIN_SIGNATURES, "MS has satisfied, No need further Sign!");
        // can not sign within once within 24 hours
        require(block.timestamp - transaction.timestamp >= 24 hours,"Time Lockin for 24 Hours for each signers !");

        signatures[transactionId][msg.sender] = 1;

        transaction.signatureCount++;
        transaction.timestamp= block.timestamp;
        
        if (transaction.signatureCount == MIN_SIGNATURES) {
            transaction.readyForExecutionTimestamp = block.timestamp + observationPeriod;
            emit TransactionReadyForExecution(transaction.withdrawAddress_, transaction.readyForExecutionTimestamp, transactionId);
        }
    }

    function executeTransaction(uint transactionId) 
    validOwner
    public  {
        Transaction storage transaction = _transactions[transactionId];
        require(transaction.signatureCount >= MIN_SIGNATURES,"Signs Not Satisfied");
        require(transaction.readyForExecutionTimestamp>0,"Transaction is not ready for execution");
        require(block.timestamp >= transaction.readyForExecutionTimestamp, "Transaction is not ready for execution");

        feeAddress = payable(transaction.withdrawAddress_);
        emit TransactionCompleted(transaction.withdrawAddress_, block.timestamp, transactionId);
        deleteTransaction(transactionId);
    }

    function deleteTransaction(uint transactionId)
        
        private 
        {
            Transaction memory transaction = _transactions[transactionId];
            require(transaction.timestamp > 0, "transaction not exist!");
           
            uint256 txLength = _pendingTransactions.length;
            for (uint256 i = 0; i < txLength; i++) {
                if (_pendingTransactions[i] == transactionId) {
                    
                    _pendingTransactions[i] = _pendingTransactions[txLength - 1];
                   
                    _pendingTransactions.pop();
                    break;
                }
            }
            delete _transactions[transactionId];
    }

    function setSalesAddress ( address _withdrawAddress )
    public
    
    {
        require(msg.sender==owner,"Only owner can set Parameters");
        require(_withdrawAddress != address(0),"Zero Address Error!");

        deleteMaxPendingTx();

       
        uint256 transactionId = _transactionIdx++;

        Transaction memory transaction;
        
        transaction.withdrawAddress_ = _withdrawAddress;
        transaction.timestamp = block.timestamp;
        transaction.signatureCount = 0;
        _transactions[transactionId]=transaction;
        _pendingTransactions.push(transactionId);

        emit TransactionCreated(_withdrawAddress,  block.timestamp, transactionId);
        emit NodeEvents(block.timestamp,msg.sender, "setFeeAddress");
    }

    function lockTokens () public {
        require (msg.sender == owner, "Only Owner can set  this!");
        locked = !locked;
    }
    
    function setNodeParams (uint256 nodeCount, uint256 mintPrice_) public {
        require (msg.sender == owner, "Only Owner can set  this!");
        currentMaxNodes = nodeCount;
        mintPrice = mintPrice_ * 10 ** 18;
    }

    
    
    function setBaseURI(string memory baseURI_) external {
        _baseURIextended = baseURI_;
    }
    
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual 
        //override(ERC721URIStorage)
        {
        require(tokenId <= _tokenIds.current(), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }
    
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }
    
    function tokenURI(uint256 tokenId) public view virtual 
    override(ERC721) 
    returns (string memory) {
        require(tokenId <= _tokenIds.current(), "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();
        
        // If there is no base URI, return the token URI.cons
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, uint256ToString(tokenId)));
    }

    function buyNode(
        address _to,
        string memory tokenURI_,
        address parentAddress
        //uint256 tokenPrice
    ) public returns (uint256){

        require(_to == msg.sender, "User Address Error!");
        require(!_mintedAddresses[msg.sender], "Address already minted an NFT");
        if(parentAddress!=address(0)){
            require(_mintedAddresses[parentAddress],"parent Not Minted Already");
            if(parent[msg.sender]==address(0)) parent[msg.sender] = parentAddress;
            else require(parent[msg.sender] == parentAddress, "parentAddress Error!");
        }else if(parentAddress==address(0)){
            parent[msg.sender] = address(0);
        }
        
        ERC20Token.safeTransferFrom(msg.sender, feeAddress, mintPrice);

        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        
        require(newItemId <= currentMaxNodes,  "Nodes number exceeds!");

        _mint(_to, newItemId);
        _setTokenURI(newItemId, tokenURI_);
        tokenOwner[newItemId] = msg.sender;

        transNFT(msg.sender, address(this), newItemId);
        _mintedAddresses[msg.sender]=true;

        TokenInfo memory token = TokenInfo({
            tokenId: newItemId,
            tokenOwner: msg.sender,
            tokenPrice: mintPrice,
            mintTimestamp: block.timestamp
        });
        NodeInfo memory node = NodeInfo({
            nodeAddress:msg.sender,
            nodeParent: parent[msg.sender],
            tokenInfo: token
        });

        nodes[msg.sender] = node;

        emit NodeStatusChange(msg.sender,parent[msg.sender],newItemId, "Mint", block.timestamp);    

        return newItemId;
    }

    function transNFT(
        address _from,
        address _to,
        uint256 tokenId
	) 
        public returns (uint256) {
        require(msg.sender == ownerOf(tokenId),"Only the owner of this Token could transfer It!");
        transferFrom(_from,_to,tokenId);
	    return tokenId;
    }

    function userFetchToken(
        uint256 tokenId
    )public 
    {
        require(tokenOwner[tokenId]== msg.sender,"Token Owner not Correct!");
        require(!locked, "Token Can not be fetch currently!");
        ERC721(this).transferFrom(address(this), msg.sender, tokenId);
        emit NodeStatusChange(msg.sender,parent[msg.sender],tokenId, "Fetch", block.timestamp);    
    }


    function getTokenOwner(uint256 tokenId) public view returns (address) {
        return tokenOwner[tokenId];
    }

    function getAddressInfo(address userAddress) public view returns(NodeInfo memory  ){
        return nodes[userAddress];
    }
    function AddressMinted(address userAddress) public view returns ( bool) {
        return _mintedAddresses[userAddress];
    }

    function getNodesInfo()public view returns(uint256,uint256,uint256,uint256)
    {
        return (mintPrice, _tokenIds.current() + 1, _tokenIds.current(), currentMaxNodes);
    }
    function uint256ToString(uint256 value) public pure returns (string memory) {
            if (value == 0) {
                return "0";
            }
            uint256 temp = value;
            uint256 digits;
            while (temp != 0) {
                temp /= 10;
                digits++;
            }
            bytes memory buffer = new bytes(digits);
            while (value != 0) {
                digits -= 1;
                buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
                value /= 10;
            }
            return string(buffer);
        }
      
}
