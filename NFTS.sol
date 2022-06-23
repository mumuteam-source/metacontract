// SPDX-License-Identifier: MIT

pragma solidity 0.8.1;

// ----------------------------------------------------------------------------
// Safe maths
// ----------------------------------------------------------------------------
library MySafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        require(c >= a);
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b <= a);
        c = a - b;
    }
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
    require(b <= a, errorMessage);
    uint256 c = a - b;

    return c;
  }
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            revert();
        }
        c = a * b;
        require(c / a == b);
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0);
        c = a / b;
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
    // Solidity only automatically asserts when dividing by 0
    require(b > 0, errorMessage);
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold

    return c;
  }
}

interface IBEP20 {
 
  function totalSupply() external view returns (uint256);
  function decimals() external view returns (uint8);
  function symbol() external view returns (string memory);
  function name() external view returns (string memory);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function allowance(address _owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

// ----------------------------------------------------------------------------
// Owned contract
// ----------------------------------------------------------------------------
contract Ownable {
    address internal owner_;
    address internal newOwner_;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    constructor() {
        owner_ = msg.sender;
    }

    function owner() external view returns (address) {
        return owner_;
    }    

    function transferOwnership(address _newOwner) external {
        require(msg.sender == owner_);
        newOwner_ = _newOwner;
    }

    function acceptOwnership() external {
        require(msg.sender == newOwner_);
        emit OwnershipTransferred(owner_, newOwner_);
        owner_ = newOwner_;
        newOwner_ = address(0);
    }
}

/**
 * The /**
  * The Delegated contract allows a set of delegate accounts
  * to perform special tasks such as admin tasks to the contract
  */
 contract MyDelegated is Ownable {
    mapping (address => bool) delegates;
    
    event DelegateChanged(address delegate, bool state);

    constructor() {
    }

    fallback() external {
    }

    function checkDelegate(address _user) internal view {
        require(_user == owner_ || delegates[_user]);
    }
    
    function checkOwner(address _user) internal view {
        require(_user == owner_);
    }
    
    function setDelegate(address _address, bool _state) external {
        checkDelegate(msg.sender);

        delegates[_address] = _state;
        
        emit DelegateChanged(_address, _state);
    }
 
    function isDelegate(address _account) external view returns (bool delegate)  {
        return (_account == owner_ || delegates[_account]);
    }
 }

// ----------------------------------------------------------------------------
// MetaCraftToken
// ----------------------------------------------------------------------------
contract MetaCraftToken is IBEP20, MyDelegated {
    using MySafeMath for uint256;

    string public _name = "MetaCraftTEST"; 
    string public _symbol = "MCRTTEST";
    uint256 public  _decimals = 18;
    uint256 internal  totalSupply_ = 0;
    bool internal halted_ = false;

    mapping(address => uint256) internal balances_;
    mapping(address => mapping(address => uint256)) internal allowed_;

    // ------------------------------------------------------------------------
    // Constructor
    // ------------------------------------------------------------------------
    constructor() {
    }

    function name() external override view returns (string memory) {
     return _name;
    }

    function symbol() external override view returns (string memory) {
        return _symbol;
    }

    function decimals() external override view returns (uint8) {
        return uint8(_decimals);
    }

    function mint(address _to, uint256 _amount) external {
        checkDelegate(msg.sender);
        require(_to != address(0));
        require(_amount > 0);

        balances_[_to] = balances_[_to].add(_amount);
        totalSupply_ = totalSupply_.add(_amount);
        emit Transfer(address(0), _to, _amount);
    }

    function burn(address _to, uint256 _amount) external {
        checkDelegate(msg.sender);
        require(_amount > 0);

        balances_[_to] = balances_[_to].sub(_amount);
        totalSupply_ = totalSupply_.sub(_amount);
        emit Transfer(_to, address(0), _amount);
    }
    // ------------------------------------------------------------------------
    // Set the halted tag when the emergent case happened
    // ------------------------------------------------------------------------
    function setEmergentHalt(bool _tag) external {
        checkOwner(msg.sender);
        halted_ = _tag;
    }

    // ------------------------------------------------------------------------
    // Total supply
    // ------------------------------------------------------------------------
    function totalSupply() external override view returns (uint256) {
        return totalSupply_;
    }

    // ------------------------------------------------------------------------
    // Get the token balance for account `tokenOwner`
    // ------------------------------------------------------------------------
    function balanceOf(address _tokenOwner) external override view returns (uint256) {
        return balances_[_tokenOwner];
    }

    // ------------------------------------------------------------------------
    // Transfer the balance from token owner's account to `to` account
    // - Owner's account must have sufficient balance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------

     function transfer(address recipient, uint256 amount) external override returns (bool) {
          require(!halted_);
         _transfer(msg.sender, recipient, amount);
    return true;
  }

    // ------------------------------------------------------------------------
    // Token owner can approve for `spender` to transferFrom(...) `tokens`
    // from the token owner's account
    //
    // https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20-token-standard.md
    // recommends that there are no checks for the approval double-spend attack
    // as this should be implemented in user interfaces 
    // ------------------------------------------------------------------------
    function approve(address _spender, uint256 _tokens) external override returns(bool){
        // require(_spender != msg.sender);
        allowed_[msg.sender][_spender] = _tokens;
        emit Approval(msg.sender, _spender, _tokens);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "MCRT: approve from the zero address");
        require(spender != address(0), "MCRT: approve to the zero address");

        allowed_[owner][spender] = amount;
        emit Approval(owner, spender, amount);
  }
    // ------------------------------------------------------------------------
    // Transfer `tokens` from the `from` account to the `to` account
    // 
    // The calling account must already have sufficient tokens approve(...)-d
    // for spending from the `from` account and
    // - From account must have sufficient balance to transfer
    // - Spender must have sufficient allowance to transfer
    // - 0 value transfers are allowed
    // ------------------------------------------------------------------------
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "MCRT: transfer from the zero address");
        require(recipient != address(0), "MCRT: transfer to the zero address");

        balances_[sender] = balances_[sender].sub(amount, "MCRT: transfer amount exceeds balance");
        balances_[recipient] = balances_[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowed_[sender][msg.sender].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
  }
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, allowed_[msg.sender][spender].add(addedValue));
        return true;
  }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, allowed_[msg.sender][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }
    // ------------------------------------------------------------------------
    // Returns the amount of tokens approved by the owner that can be
    // transferred to the spender's account
    // ------------------------------------------------------------------------
    function allowance(address _tokenOwner, address _spender) external override view returns (uint256) {
        return allowed_[_tokenOwner][_spender];
    }

    // ------------------------------------------------------------------------
    // Owner can transfer out any accidentally sent ERC20 tokens
    // ------------------------------------------------------------------------
    function transferAnyERC20Token(address _tokenAddress, uint256 _tokens) external {
        checkOwner(msg.sender);
        IBEP20(_tokenAddress).transfer(owner_, _tokens);
    }
}