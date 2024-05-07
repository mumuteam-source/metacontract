// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";   
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";


contract MetaCraftVNode is ERC721, IERC721Receiver,ReentrancyGuard{
    // ERC20 token used for minting NFT
    using ECDSA for bytes32;
    IERC20 public immutable ERC20Token;
    uint256 public immutable tokenDecimals;
    using SafeERC20 for IERC20;
    uint256 public _tokenIds;
    address private immutable owner;
   
    // Mapping to track minted addresses
    mapping(address => bool) public _mintedAddresses;
    //tokenURI
    string public constant nodeTokenURI = "ipfs://QmZ1n7S2UHFmBbiGFzFHYsTJoLwbU29rTDquxPccSNqajg";
    // Price in ERC20 tokens to mint NFT
    uint256 public mintPrice;
    bool public locked = true;
    bool public halted = false;

    
    // Optional mapping for token URIs
    //mapping (uint256 => string) private _tokenURIs;
    // address's parent
    mapping (address=>address) public parent;
    // tokenOwner
    mapping (uint256=>address) public tokenOwner;
    mapping (address => NodeInfo) public nodes;

    uint256 constant public PRICE_INCREMENT = 500;//500
    uint256 constant public ID_INCREMENT = 5; //500
    uint256 constant public MAX_ID = 50000;

    address public publicKey = address(0xEe8b45a0c599e8E6512297f99687BF5FE3359147);
    address payable  public feeAddress = payable(address(0x498d09597e35f00ECaB97f5A10F6369aDde00364));
    // Event emitted when an NFT is minted

    event NodeStatusChange(address owner, address parent, uint256  tokenId, string status, uint256 timestamp);
    //event TransactionCreated(address withdrawAddress,  uint256 timestamp, uint256 transactionId);
    //event TransactionCompleted(address withdrawAddress,  uint256 timestamp, uint256 transactionId);
    event TransactionSigned(address by, uint transactionId);

    event NodeEvents(
        uint256 timeStamp,
        address eventSender,          
        string  eventName
    );

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
    enum TransactionType {
        AddOwner,
        RemoveOwner,
        SetParameter,
        SetSalesAddress
    }
    struct SetTransaction {
        TransactionType txType;
        bytes data;
        uint8 signatureCount;
        uint256 timestamp;
        uint256 readyForExecutionTimestamp; 
        bool executed;
    }

    mapping(uint => SetTransaction) private _settransactions;

    uint[] private _pendingTransactions;

    mapping(uint => mapping(address => bool)) private signatures;


    modifier notExecuted(uint transactionId) {
        SetTransaction memory transaction = _settransactions[transactionId];
        require(transaction.timestamp > 0, "transaction not exist!");
        require(!_settransactions[transactionId].executed, "Transaction already executed");
        _;
    }

    mapping(address => uint8) private _validOwners;
    //mapping ( uint=>mapping(address => uint8)) signatures;
    //mapping (uint => Transaction) private _transactions;
    //uint[] private _pendingTransactions;
    uint256 public constant observationPeriod = 24 hours; //hours
    uint256 public constant maxPendingTime = 96 hours; // hours

    uint constant MIN_SIGNATURES = 3;
    uint private _transactionIdx;

    constructor(
        string memory _name,
        string memory _symbol,
        address _erc20Token,
        uint256 _decimals
        //uint256 _mintPrice
    ) ERC721(_name, _symbol) {
        ERC20Token = IERC20(_erc20Token);
        tokenDecimals = _decimals;
        owner = msg.sender;
       

       _validOwners[address(0x486d3D3e599985B00547783E447c2d799d7d2eE5)] = 1;
       _validOwners[address(0x498d09597e35f00ECaB97f5A10F6369aDde00364)] = 1;
       _validOwners[address(0xa1813Fb2A6882E8248CD4d4C789480F50CAf7ca4)] = 1;
    }

    function onERC721Received(address, address, uint256, bytes calldata)
    external 
    override
    pure
    returns(bytes4)
    {
        //tokenOwner[tokenId] = from;
        return this.onERC721Received.selector;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "Unauthorized: can only be called by the contract itself");
        _;
    }

    modifier validOwner() {
        require(_validOwners[msg.sender] == 1, "not Authorized Mulsig User !");
        _;
    }

    function addOwner(address _owner)
        public 
        {
            require(msg.sender==owner,"Only owner can set Parameters");
            require(_owner != address(0),"Zero Address Error!");
           
            TransactionType txType = TransactionType.AddOwner;
            bytes memory data = abi.encodeWithSelector(this.setOwner.selector, _owner, 1);
            addSetTransaction(txType, data);
            
            emit NodeEvents(block.timestamp,msg.sender, "AddValieOwner");
    }

    function removeOwner(address _owner)
        public {
            require(msg.sender==owner,"Only owner can set Parameters");
            require(_owner != address(0),"Zero Address Error!");
            
            TransactionType txType = TransactionType.RemoveOwner;
            bytes memory data = abi.encodeWithSelector(this.setOwner.selector, _owner, 0);
            addSetTransaction(txType, data);
            
           
            emit NodeEvents(block.timestamp,msg.sender, "RemoveValieOwner");
    }
    
   
    function setParameters ( bool isLock_, bool isHalt_)
    public
    {
        require(msg.sender==owner,"Only owner can set Parameters");
       
    
        TransactionType txType = TransactionType.SetParameter;
        bytes memory data = abi.encodeWithSelector(this.setLockHalt.selector, isLock_, isHalt_);
        addSetTransaction(txType, data);

        emit NodeEvents(block.timestamp,msg.sender, "setParamters");
    }

    function setSalesAddress ( address _feeAddress)
    public
    {
        require(msg.sender==owner,"Only owner can set Parameters");
       
        //deleteMaxPendingTx();
        TransactionType txType = TransactionType.SetSalesAddress;
        bytes memory data = abi.encodeWithSelector(this.setFeeAddress.selector, _feeAddress);
        addSetTransaction(txType, data);

        emit NodeEvents(block.timestamp,msg.sender, "setSalesAddress");
    }

   function isValidFunctionSelector(TransactionType _type, bytes4 selector) private pure returns (bool) {
        if (_type == TransactionType.AddOwner && selector == this.setOwner.selector) return true;
        if (_type == TransactionType.RemoveOwner && selector == this.setOwner.selector) return true;
        if (_type == TransactionType.SetParameter && selector == this.setLockHalt.selector) return true;
        if (_type == TransactionType.SetSalesAddress && selector == this.setFeeAddress.selector) return true;
        return false;
    }
    function  deleteMaxPendingTx()

    private 
    {
         require(_pendingTransactions.length <= 1,"has pending txs! Please sign them first");   
         
         if(_pendingTransactions.length == 1 ){
                uint txId = _pendingTransactions[0];
                
                SetTransaction storage pendingsetTx = _settransactions[txId];
                               
                //for set param Txs
                if (pendingsetTx.timestamp > 0 ){
                    if (block.timestamp - pendingsetTx.timestamp > maxPendingTime){
                        deleteSetTx(txId);
                    }else revert("has pending txs yet! Please sign them first"); 
                }

            }
    }

    function setOwner(address _owner, uint8 _status) public onlySelf {
        _validOwners[_owner] = _status;
    }
    function setLockHalt(bool isLock_, bool isHalt_ ) public onlySelf{
        locked=isLock_;
        halted = isHalt_;
    }
    function setFeeAddress(address _feeAddress) public onlySelf{
        feeAddress = payable(_feeAddress);
    }

    function addSetTransaction(TransactionType _type, bytes memory _data) private {
        require(msg.sender == owner,"Only owner can set Parameters");
        require(_data.length >= 4, "Data too short for a valid function selector");
        require(isValidFunctionSelector(_type, bytes4(_data)), "Invalid function selector for transaction type");
        
        deleteMaxPendingTx();

        uint256 transactionId = _transactionIdx++;

        _settransactions[transactionId] = SetTransaction({
            txType: _type,
            data: _data,
            signatureCount: 0,
            timestamp: block.timestamp,
            readyForExecutionTimestamp:block.timestamp,
            executed: false
        });
        _pendingTransactions.push(transactionId);
        
    }
    // Function for authorized owners to sign pending transactions
    function signSetTransaction(uint transactionId) public validOwner notExecuted(transactionId) {
        SetTransaction memory transaction = _settransactions[transactionId];
        require(transaction.timestamp > 0, "transaction not exist!");
        require(!transaction.executed, "Transaction already executed");

        require(!signatures[transactionId][msg.sender], "Signature already provided");

        if (transaction.txType == TransactionType.SetSalesAddress){
           require(block.timestamp - transaction.timestamp >= 24 hours,"Time Lockin for 24 Hours for each signers !"); //hours
        }

        signatures[transactionId][msg.sender] = true;
        _settransactions[transactionId].signatureCount++;
        _settransactions[transactionId].timestamp = block.timestamp;
        
        if (_settransactions[transactionId].signatureCount == MIN_SIGNATURES) {
                if (transaction.txType == TransactionType.SetSalesAddress){
              _settransactions[transactionId].readyForExecutionTimestamp = block.timestamp + observationPeriod;  
           }
           else{
              _settransactions[transactionId].readyForExecutionTimestamp = block.timestamp;
              executeSetTransaction(transactionId);
           }
            
        }
        emit TransactionSigned(msg.sender, transactionId);

    }

   function executeSetTransaction(uint transactionId) 
    validOwner
    public  {
        SetTransaction storage transaction = _settransactions[transactionId];
        require(transaction.signatureCount >= MIN_SIGNATURES,"Signs Not Satisfied");
        require(transaction.readyForExecutionTimestamp>0,"Transaction is not ready for execution");
        require(block.timestamp >= transaction.readyForExecutionTimestamp, "Transaction is not ready for execution");

        (bool success,) = address(this).call(transaction.data);
        require(success, "Transaction execution failed");

        transaction.executed = true;
        deleteSetTx(transactionId);
    }

    function deleteSetTx(uint transactionId)
        
        private {
            SetTransaction memory transaction = _settransactions[transactionId];
            require(transaction.timestamp > 0, "transaction not exist!");
           
            uint256 txLength = _pendingTransactions.length;
            for (uint256 i = 0; i < txLength; i++) {
                if (_pendingTransactions[i] == transactionId) {
                    
                    _pendingTransactions[i] = _pendingTransactions[txLength - 1];
                   
                    _pendingTransactions.pop();
                    break;
                }
            }
            delete _settransactions[transactionId];
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
      returns ( SetTransaction memory) {
        //Transaction storage pendingwithdrawTx = _transactions[transactionId];
        SetTransaction memory pendingsetTx = _settransactions[transactionId];
        return pendingsetTx;
    }
    function  getValidOwner(address _owner)  view public returns (uint){

        return _validOwners[_owner];
    }

    
    /*****************************************************/


    function tokenURI(uint256 tokenId) public view virtual 
    override(ERC721) 
    returns (string memory) {
        require(tokenId <= _tokenIds, "ERC721Metadata: URI query for nonexistent token");

        // string memory _tokenURI = _tokenURIs[tokenId];
       
        return nodeTokenURI;
        
    }

    function buyNode(
        uint256 timestamp,
        bytes32 nonce,
        //bytes32 message,
        bytes calldata signature,
        address parentAddress,
        uint256 maxPrice
    ) 
    nonReentrant 
    notContract
    external  
    returns (uint256){
        require(!halted, "Node Halted!");
        
        bytes32 challenge = getChallenge(timestamp, nonce, parentAddress, msg.sender);
        //require(message == challenge,"message not correct!");
        bool isVerified = verified(publicKey,challenge, signature);
        require(isVerified, "Verify Error!");
        //require(_to == msg.sender, "User Address Error!");
        require(!_mintedAddresses[msg.sender], "Address already minted an NFT");
        if(parentAddress!=address(0)){
            require(_mintedAddresses[parentAddress],"parent Not Minted Already");
            if(parent[msg.sender]==address(0)) parent[msg.sender] = parentAddress;
            else require(parent[msg.sender] == parentAddress, "parentAddress Error!");
        }else if(parentAddress==address(0)){
            parent[msg.sender] = address(0);
        }
        
        
        uint256 newItemId =++_tokenIds;

        mintPrice = calculatePrice(newItemId);
        require(mintPrice <= maxPrice, "price overflow");
        
        ERC20Token.safeTransferFrom(msg.sender, feeAddress, mintPrice);

        _mint(address(this), newItemId);
        
        tokenOwner[newItemId] = msg.sender;

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


    function userFetchToken(
        uint256 tokenId,
        address receiver
    )
    public 
    nonReentrant 
    notContract
    {
        require(tokenOwner[tokenId]== msg.sender,"Token Owner not Correct!");
        //require(tokenOwner[tokenId] == receiver, "Token receiver not Correct!");
        require(!locked, "Token Can not be fetch currently!");
        ERC721(this).safeTransferFrom(address(this), receiver, tokenId);
        emit NodeStatusChange(msg.sender,parent[msg.sender],tokenId, "Fetch", block.timestamp);    
    }


    function getTokenOwner(uint256 tokenId) public view returns (address) {
        return tokenOwner[tokenId];
    }
    function ownerOf(uint256 tokenId) public override view returns (address) {
        address currentOwner = super.ownerOf(tokenId);
        if(currentOwner == address(this)) return tokenOwner[tokenId];
        else return super.ownerOf(tokenId);
    }
    
    function getAddressInfo(address userAddress) public view returns(NodeInfo memory  ){
        return nodes[userAddress];
    }
    function AddressMinted(address userAddress) public view returns ( bool) {
        return _mintedAddresses[userAddress];
    }

    function getNodesInfo()public view returns(uint256,uint256,uint256,uint256)
    {
        uint256 currentTokenId = _tokenIds;
        uint256 nextPrice = calculatePrice(currentTokenId+1);
        return (nextPrice, currentTokenId+1, currentTokenId,mintPrice);
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
     //get Challenge
    function getChallenge(uint256 timestamp,
                              bytes32 nonce, 
                            address parentAddress,
                              address userAddress
                             ) public pure returns (bytes32){
        
        bytes32 challenge = keccak256(abi.encodePacked( userAddress, timestamp, nonce, parentAddress));
       
        return challenge;   
    }
     function verified(
        address expectedSigner,
        bytes32 messageHash,
        bytes memory signature
    ) public pure returns (bool) {
        // Compute the message hash that was originally signed, prefixed according to the Ethereum standard.
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        //bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        
        // Recover the signer address from the signature using the ECDSA library.
        address recoveredSigner = ethSignedMessageHash.recover(signature);

        // Return true if the recovered signer matches the expected signer, otherwise false.
        return (recoveredSigner == expectedSigner);
    }

   
    function getEthSignedMessageHash(bytes32 _messageHash) private  pure returns (bytes32) {
      
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }


    //not contract address
    modifier notContract() {
    require((!_isContract(msg.sender)) && (msg.sender == tx.origin), "contract not allowed");
    _;
    }

    function _isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function calculatePrice(uint256 id) public view   returns (uint256) {
      
        require(id<= MAX_ID,"ID exceeds maximum limit");

        uint256 priceLevel = ((id-1) / ID_INCREMENT) + 1;
        return priceLevel * PRICE_INCREMENT * 10** tokenDecimals ;
       
    }
       
}
