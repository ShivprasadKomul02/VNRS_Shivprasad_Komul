// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


//VNRS-Vanity Name Registration System
/*
Solution 2: preRegistering vanityname

To aviod frontrunning I have splitted the registration of the name in two steps.

1-PreRegiter the name:
   The user has to call the function preRegister passing the name hashed with the name's owner address.
    Once the preRegister is completed, the user has to wait 5 minutes to register the name
2-Register: 
    - The user has to call the register function with the name in string format. 
    - The function checks if there is a preregister for the following name and sender address
      and 5 minutes have passed from the PreRegiter. 
    - Then  it registers the name. 
    - For a malicious node, it is impossible to delay the transaction to be commited to the 
      blockchain by frontrunner/malioious nodes for 5 minutes since the user register the name 
     and it doesn't have enough time to make the preRegister before the other call is commited.


below code is solution to the problem using preRegister.
*/

contract VNRS_SENIOR is Ownable{

    using SafeMath for uint;
    uint lockamount=0.005 ether; //amount to lock
    uint lockperiod= 1 minutes;  //timeperiod to lock(for testing we can change it to "1 minutes"
    uint priceperchar=0.0005 ether; //fees to calulate price of each char in vanityname
    uint feesamount=0;              //fess amount to register vanityname
    uint constant MIN_LEN = 3; //min length of vanity  name should be 3 chars
    uint constant MAX_LEN = 20;//max length of vanity  name should be 3 chars
    uint public constant FRONTRUN_TIME = 5 minutes;//  user has to wait 5 min to omplete registration process after preregistration process.
    
    

    //Vanity Name structure 
    struct VanityName
    {
        string name;
        uint expirydate;
        address owner;
        uint lockedBal;
    }

    //mapping of vanity names 
    mapping(string=>VanityName) vanityNames;
    mapping(string => uint256) public preRegisters;

    //Events for vaious functions
    event VanityNameRegistered(string name, address owner, uint256 indexed timestamp);
	event VanityNameRenewed(string name, address owner, uint256 indexed timestamp);
	event AmountUnlocked(string name, uint256 indexed timestamp);
    

    //function to set amount to lock 
    //allowed to call this only by deployer of contract
    function setLockAmount(uint _lockamount) public onlyOwner{
       
        lockperiod=_lockamount;
    }
    
    //function to set timeperiod  to lock  vanityName  
    //allowed to call this only by deployer of contract
    function setLockPeriod(uint _lockperiod) public onlyOwner{
        
        lockperiod=_lockperiod;
    }

    //function to change prices per chhar of fees for registration  
    //allowed to call this only by deployer of contract
    function setPriceperChar(uint _price) public onlyOwner{
        priceperchar=_price;
    }

    //returns lock amount 
    function getLockAmount() public view returns(uint)
    {
        return lockamount;
    }
    //returns lockperiod
    function getLockPeriod() public view returns(uint)
    {
        return lockperiod;
    }
    //returns prices per char for calculation of fees
    function getPriceperChar() public view returns(uint)
    {
        return priceperchar;
    }
    
   

   //modifier to check calling from vanityName owner or not
    modifier isNameOwner(string memory _vName)
    {
        string memory vNameHash = bytes32ToString(encrypt(_vName));
        require(vanityNames[vNameHash].owner==msg.sender && vanityNames[vNameHash].expirydate > block.timestamp,"You are not the Owner of this Vanity Name");
        _;
    }

     //modifier to check if name is available to register or not
    modifier isNameAvailable(string memory _vName) 
    {
        string memory vNameHash = bytes32ToString(encrypt(_vName));
        require(vanityNames[vNameHash].expirydate < block.timestamp || vanityNames[vNameHash].expirydate == 0,"Vanity Name is not Available");
        _;
    }

    //modifier to check funds are sufficient to register the vanityName or not
    //total amount = fees(vName)+lockamount
    modifier isMoneyAvailable(string memory _vName)
    {
        uint namePrice=calculatePrice(_vName);
        uint finalAmt=lockamount.add(namePrice);

        require(msg.value>=finalAmt,"Insufficent funds");

        _;
    }
    //modifier to check size of the vanityName
    //min_len=3 chars and max_len=20 chars
    modifier isValidName(string memory _vName)
    {
        
        require(bytes(_vName).length>=MIN_LEN && bytes(_vName).length <=MAX_LEN,"Vanity Name size must be >=3 and <=20");
    _;
    }

    //checks if user preRegistered the vanityname or not
    modifier isRegistrationOpen(address _sender, string memory _vName) {
		string memory secret = bytes32ToString(keccak256(abi.encodePacked(_sender, _vName)));
		require(preRegisters[secret] > 0,"Vanity Name not preregistered");
		require(block.timestamp > preRegisters[secret] + FRONTRUN_TIME,"Registration not unlocked yet. wait 5 minutes");
		_;
	}

    //function to encrypt vName for mapping
    function encrypt(string memory _vName) public view returns (bytes32)
    {
        return keccak256(abi.encodePacked(_vName));
    }
    //funciton to calculate total fees to register vanityName
    function calculatePrice(string memory _vName) public view returns(uint)
    {
        uint namePrice=bytes(_vName).length.mul(priceperchar);
        return namePrice;
    }

    //function to convert bytes32 to string data
  function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    //function to register vanityname
    //3 conditons must be satisfied in order to register vanity name
    //isValidName,isNameAvailable,isMoneyAvailable
    function regiterVanityName(string memory _vName,uint _txCounter) public payable 
    isRegistrationOpen(msg.sender,_vName) 
    isValidName(_vName) 
    isNameAvailable(_vName) 
    isMoneyAvailable(_vName)
    {
     
        string memory vNameHash= bytes32ToString(encrypt(_vName));
        uint finalPrice=calculatePrice(_vName);
        
        VanityName memory vname = VanityName({
            name:_vName,
            expirydate: block.timestamp + lockperiod,
            owner:msg.sender,
            lockedBal:msg.value.sub(finalPrice)
        });

        vanityNames[vNameHash]=vname;
        address payable _owner = payable(owner());
        feesamount=msg.value;
        bool success=_owner.send(feesamount);
        feesamount=0;
        require(success,"Error sending fees to owner");

        
        emit VanityNameRegistered(_vName,msg.sender,block.timestamp);

        
    }

    //function to renewVanityName
    //allowed to call only from owner of vanityname with sufficient funds
    function renewVanityName(string memory _vName,uint _txCounter) public payable isNameOwner(_vName) isMoneyAvailable(_vName)
    {
      
         string memory vNameHash=bytes32ToString(encrypt(_vName));
         uint finalPrice=calculatePrice(_vName);

        require(msg.value==finalPrice.add(lockamount),"Insuffient funds to renew Vanity Name");
        vanityNames[vNameHash].expirydate+=lockperiod;
        address payable _owner = payable(owner());
        feesamount=msg.value;
        bool success=_owner.send(feesamount);
        feesamount=0;
        require(success,"Error sending fees to owner");

        emit VanityNameRenewed(_vName,msg.sender,block.timestamp);

    }

    //function to release funds hold while registration 
    //vanityName must be expired inorder to unlock locked amount
    function unLockAmount(string memory _vName) public
    {
         string memory vNameHash=bytes32ToString(encrypt(_vName));
        require(vanityNames[vNameHash].owner == msg.sender ,"You are not the owner of vanity Name");
         require(vanityNames[vNameHash].lockedBal > 0,"Nothing to unlock");
         require(vanityNames[vNameHash].expirydate <  block.timestamp ,"Expiry date is not due can't unlock funds" );
        
        address payable _sender = payable(msg.sender);
        feesamount=vanityNames[vNameHash].lockedBal;
        vanityNames[vNameHash].lockedBal=0;
        _sender.transfer(feesamount);
       
        emit AmountUnlocked(_vName,block.timestamp);
    }

    //returns ercryted hash by taking valnityName and address of msg.sender
    function getPreRegisterHash(string memory _vName) public view returns (bytes32)
	{	
        return keccak256(abi.encodePacked(msg.sender, _vName));
	}
    //function preregsiters the vanity name to avoid frontrunning
    function preRegister(string memory _hash) external {
		preRegisters[_hash] = block.timestamp;
	}
}