// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";   
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


contract MetaCraftVNode is ERC721, IERC721Receiver,ReentrancyGuard{
    // ERC20 token used for minting NFT
    
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
    uint256 public  mintPrice;
    bool public locked = true;
    bool public halted = false;

    
      // Optional mapping for token URIs
    mapping (uint256 => string) private _tokenURIs;
    // address's parent
    mapping (address=>address) public parent;
    // tokenOwner
    mapping (uint256=>address) public tokenOwner;
    mapping (address => NodeInfo) public nodes;

    uint256 constant public PRICE_INCREMENT = 500;
    uint256 constant public ID_INCREMENT = 500;
    uint256 constant public MAX_ID = 50000;

    address public publicKey = address(0xEe8b45a0c599e8E6512297f99687BF5FE3359147);
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
      bool locked_;
      uint256 nodeCount_;
      uint256 mintPrice_;
      uint8 signatureCount;
      uint256 readyForExecutionTimestamp; 
      uint256 timestamp;
    }

     struct TxSetParam {
      bool locked_;
      bool halted_;
      uint8 signatureCount;
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

    mapping(address => uint8) private _validOwners;
    mapping ( uint=>mapping(address => uint8)) signatures;
    mapping (uint => Transaction) private _transactions;
    uint[] private _pendingTransactions;
    uint256 public constant observationPeriod = 24 hours ;
    uint256 public constant maxPendingTime = 96 hours;

    mapping (uint => TxAddOwner) private _txaddowners;
    mapping (uint => TxDelOwner) private _txdelowners;
    mapping (uint => TxSetParam) private _txsetparams;

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
    modifier validOwner() {
        require(_validOwners[msg.sender] == 1, "not Authorized Mulsig User !");
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
                TxSetParam storage pendingsetTx = _txsetparams[txId];
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

                //for set param Txs
                if (pendingsetTx.timestamp > 0 ){
                    if (block.timestamp - pendingsetTx.timestamp > maxPendingTime){
                        deleteSetParamTx(txId);
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
                    _validOwners[(transaction.owner)]=1;
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
                    _validOwners[transaction.owner]=0;
                
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

    function setParameters ( bool isLock_, bool isHalt_)
    public
    {
        require(msg.sender==owner,"Only owner can set Parameters");
       
        deleteMaxPendingTx();

        uint256 transactionId = _transactionIdx++;

        TxSetParam memory transaction;
        
       
        transaction.locked_ = isLock_;
        transaction.halted_ = isHalt_;
        
        transaction.timestamp = block.timestamp;
        transaction.signatureCount = 0;
        _txsetparams[transactionId]=transaction;
        _pendingTransactions.push(transactionId);

        emit TransactionCreated(msg.sender,  block.timestamp, transactionId);
        emit NodeEvents(block.timestamp,msg.sender, "setParamters");
    }

    function signSetParam(uint transactionId)
      validOwner
      public {

            TxSetParam storage transaction = _txsetparams[transactionId];

            // Transaction must exist
            
            // Cannot sign a transaction more than once
            require(signatures[transactionId][msg.sender] != 1, "Can't Sign Again with the same Account!");
            signatures[transactionId][msg.sender] = 1;

            transaction.signatureCount++;
            transaction.timestamp= block.timestamp;

            emit TransactionSigned(msg.sender, transactionId);
           
            if (transaction.signatureCount >= MIN_SIGNATURES) {
                    locked = transaction.locked_;
                    halted = transaction.halted_;
                    
                    emit TransactionCompleted(msg.sender, block.timestamp, transactionId);
                    deleteSetParamTx(transactionId);
            }
    }
    function deleteSetParamTx(uint transactionId)
        
        private {
            TxSetParam memory transaction = _txsetparams[transactionId];
            require(transaction.timestamp > 0, "transaction not exist!");
           
            uint256 txLength = _pendingTransactions.length;
            for (uint256 i = 0; i < txLength; i++) {
                if (_pendingTransactions[i] == transactionId) {
                    
                    _pendingTransactions[i] = _pendingTransactions[txLength - 1];
                   
                    _pendingTransactions.pop();
                    break;
                }
            }
            delete _txsetparams[transactionId];
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
      returns (Transaction memory, TxAddOwner memory, TxDelOwner memory, TxSetParam memory) {
        Transaction storage pendingwithdrawTx = _transactions[transactionId];
        TxAddOwner storage pendingaddTx = _txaddowners[transactionId];
        TxDelOwner storage pendingdelTx = _txdelowners[transactionId];
        TxSetParam storage pendingsetparamTx = _txsetparams[transactionId];
        return (pendingwithdrawTx,pendingaddTx,pendingdelTx,pendingsetparamTx);
    }
    function  getValidOwner(address _owner)  view public returns (uint){
       
        return _validOwners[_owner];
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

    function setSalesAddress ( address _withdrawAddress)
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
    
    

    function tokenURI(uint256 tokenId) public view virtual 
    override(ERC721) 
    returns (string memory) {
        require(tokenId <= _tokenIds, "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
       
        return _tokenURI;
        
    }

    function buyNode(
        uint256 timestamp,
        bytes32 nonce,
        bytes32 message,
        bytes memory signature,
        address parentAddress,
        uint256 maxPrice
    ) 
    nonReentrant 
    notContract
    external  
    returns (uint256){
        require(!halted, "Node Halted!");
        
        bytes32 challenge = getChallenge(timestamp, nonce, parentAddress, msg.sender);
        require(message == challenge,"message not correct!");
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
        _mint(msg.sender, newItemId);
        //_setTokenURI(newItemId, nodeTokenURI);
        _tokenURIs[newItemId] = nodeTokenURI;
        tokenOwner[newItemId] = msg.sender;

        transferFrom(msg.sender, address(this), newItemId);
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
        require(tokenOwner[tokenId] == receiver, "Token receiver not Correct!");
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

    function getNodesInfo()public view returns(uint256,uint256,uint256)
    {
        uint256 currentTokenId = _tokenIds;
        return (mintPrice, currentTokenId+1, currentTokenId);
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
    ) public  pure returns (bool) {     
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);
        address recoveredSigner = ECDSA.recover(ethSignedMessageHash, signature);
        require(recoveredSigner == expectedSigner, "Invalid signature");

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        require(ecrecover(ethSignedMessageHash, v, r, s) == expectedSigner, "Invalid signature malleability");

        return true;
    }

    function checkVerify(
        address signer,
        bytes32 message,
        bytes memory signature
    ) public pure returns (address,address)
    {
        
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(message);
        address recovered = ecrecover(ethSignedMessageHash, v, r, s);

        address recoveredSigner = ECDSA.recover(ethSignedMessageHash, signature);
        require(recoveredSigner == signer, "Invalid signature");

       return (recoveredSigner, recovered);
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
        if (id > MAX_ID) {
            revert("ID exceeds maximum limit");
        }

        uint256 priceLevel = ((id-1) / ID_INCREMENT) + 1;
        return priceLevel * PRICE_INCREMENT * 10** tokenDecimals;
    }
      
}
