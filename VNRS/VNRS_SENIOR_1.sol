// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.6;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


   
    /*
    Solution 1: Using Transaction ordering

    Solution for frontrunning is to use a transaction counter to “lock” in the agreed price to register name
    1.when user registers vanity name by entering transaction counter no 
    2.Then registerVanityName trnsaction gets included in transaction(mem) pool of miners.
    3.Then owner is trying to frontrun transaction by calling setPriceperChar 
    and increasing feesamount to register by setting very high gas price.
        * Solution for this frontrunning:
            -increamenting txCounter(transaction counter) by 1 
    4.so owners transaction will mined first before user registration for vanity name
    5.then txCounter is increased when owners transaction gets mined first
    5.when the users VanityNameRgistration transaction trying to confirm it gets failed
     becauuse txCounter was increased.

    In this way using "Transaction Ordering"  technique we can write smart contract against frontrunning bots/nodes. 
    Below code shows the solution to the problem.
    */
 

//VNRS-Vanity Name Registration System
//Smart contract against frontrunning using "Transaction Ordering" technique.
contract VNRS_SENIOR is Ownable{

    using SafeMath for uint;
    uint lockamount=0.005 ether; //amount to lock
    uint lockperiod= 1 minutes;  //timeperiod to lock(for testing we can change it to "1 minutes"
    uint priceperchar=0.0005 ether; //fees to calulate price of each char in vanityname
    uint feesamount=0;              //fess amount to register vanityname
    uint constant MIN_LEN = 3; //min length of vanity  name should be 3 chars
    uint constant MAX_LEN = 20;//max length of vanity  name should be 3 chars

    uint public txCounter=0;//counter for transaction ordering
   

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

    //Events for vaious functions
    event VanityNameRegistered(string name, address owner, uint256 indexed timestamp);
	event VanityNameRenewed(string name, address owner, uint256 indexed timestamp);
	event AmountUnlocked(string name, uint256 indexed timestamp);
    

    //function to set amount to lock 
    //allowed to call this only by deployer of contract
    function setLockAmount(uint _lockamount) public onlyOwner{
        txCounter+=1;
        lockperiod=_lockamount;
    }
    
    //function to set timeperiod  to lock  vanityName  
    //allowed to call this only by deployer of contract
    function setLockPeriod(uint _lockperiod) public onlyOwner{
         txCounter+=1;
        lockperiod=_lockperiod;
    }

    //function to change prices per chhar of fees for registration  
    //allowed to call this only by deployer of contract
    function setPriceperChar(uint _price) public onlyOwner{
         txCounter+=1;
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
    function regiterVanityName(string memory _vName,uint _txCounter) public payable isValidName(_vName) isNameAvailable(_vName) isMoneyAvailable(_vName)
    {
        require(txCounter==_txCounter,"Frontrunning");
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
        require(txCounter==_txCounter,"Frontrunning");
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
}