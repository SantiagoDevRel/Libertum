// SPDX-License-Identifier: UNLICENSED

// Pragma statements
// ------------------------------------
pragma solidity ^0.8.10;
pragma abicoder v2;

// Import statements
// ------------------------------------
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";

// ~~~~~~~~~~~~~~ Contract ~~~~~~~~~~~~~~
//
contract Launchpad is Ownable, ReentrancyGuard, PaymentSplitter {

    IERC20 public immutable mainCurrency; //ERC20 needed to buy this projectToken
    IERC20 public immutable projectToken; //ERC20 of the project
    uint256 public s_projectPrice; //price in _mainCurrency token
    uint256 public s_projectSupply; //Initial supply of the project Token
    uint256 public s_collectedAmount; //_mainCurrency collected
    uint256 public s_minimumAmountToPurchase; //minimum quantity of tokens the users can buy
    bool public s_isActive;
    address[] private s_partners;
    mapping (address => uint256) public s_tokensPurchased;
   
    // ~~~~~~~~~~~~~~ Events ~~~~~~~~~~~~~~
    //

    event RoundFinished(uint time, uint collectedAmount);
    event TokensBought(IERC20 token, address indexed buyer, uint256 amount);
    event SupplyAdded(address from, uint256 amount);
    event SupplyReduced(address to, uint256 amount);    
    event FundsCollectedLibertum(IERC20 indexed project, address indexed Libertum, uint256 amount);
    event FundsCollectedProjectOwner(IERC20 indexed project, address indexed ProjectOwner, uint256 amount);
    event FundsCollectedLP(IERC20 indexed project, address indexed LP, uint256 amount);


    // ~~~~~~~~~~~~~~ Functions ~~~~~~~~~~~~~~
    //
    constructor(
        IERC20 mainCurrency_, 
        IERC20 projectToken_,
        uint256 projectPrice_,
        uint256 minAmountToPurchase_, 
        address[] memory payees_, 
        uint[] memory shares_) 
    PaymentSplitter(payees_, shares_) {
        mainCurrency = mainCurrency_;
        projectToken = projectToken_;
        s_projectPrice = projectPrice_;
        s_projectSupply = 0; 
        s_minimumAmountToPurchase = minAmountToPurchase_;
        s_isActive = true;
        s_partners = payees_;
        //Set the total sum of shares to be 100 would be better to assign percentages to the payees
        //Example: 30 shares to "X", 20 shares to "Y" and 50 shares to "P" = 100 shares(100%)
    }

    /*
        finishRound() onlyowner
        * Function to close the round for this project
        * 1. close the round, updating state variables
        * 2. call _sendFunds() and require to return true
        * 3. emit event
    */

    function finishRound() external onlyOwner {
        require(s_isActive, "Launchpad: Round is over.");
        s_isActive = false;
        //s_collectedAmount = 0;
        require(_sendFunds(),"Launchpad: Unable to send funds.");
        emit RoundFinished(block.timestamp, s_collectedAmount);
    }

    /*
        _sendFunds() internal
        * 1. copy in memory the partners length
        * 2. make a for loop to send the tokens using PaymentSplitter
        * 3. return true
    */
    function _sendFunds() internal returns(bool) {
        uint partnersLength = s_partners.length;
        for(uint i=0;i<partnersLength;){
            PaymentSplitter.release(mainCurrency, s_partners[i]);
            unchecked{
                i++;
            }
        }
        return true;
    }
 


    /*
        addSupply() 
        1. FRONTEND: from_ address must approve tokens first & decimals
        2. execute transferFrom to this contract to add projectToken
        3. update projectSupply variable
        4. emit event
    */
    function addSupply(address from_, uint256 amount_) external onlyOwner {
        require(projectToken.transferFrom(from_, address(this), amount_), "Launchpad: Failed adding supply");
        s_projectSupply += amount_;
        emit SupplyAdded(from_, amount_);
    }

    /*
        reduceSupply()
        1. send tokens from this contract to to_
        2. update projectSupply variable
    */
    function reduceSupply(address to_, uint256 amount_) external onlyOwner{
        require(projectToken.transfer(to_, amount_), "Failed transfering the tokens");
        s_projectSupply -= amount_;
        emit SupplyReduced(to_, amount_);
    }
    
    /*
        buyTokens() public
        * 1. FRONTEND: Approve() tokens from the msg.sender & decimals
        * 2. require isActive & there is enough supply.
        * 3. calculate the total amount of mainCurrency to transferFrom msg.sender
        * 4. update state variables
        * 4. transferFrom() mainCurrency from msg.sender to this contract
        * 5. transfer() projectTokens to the user
    */
    function buyTokens(uint256 amountToBuy_) external nonReentrant returns (bool) {
        require(s_isActive, "Launchapad: Round is over");
        require(s_minimumAmountToPurchase <= amountToBuy_,"Launchpad: Amount is less than the minimum amount you may purchase");
        require(s_projectSupply >= amountToBuy_, "Launchpad: Not enough supply");
        uint amountMainCurrency = amountToBuy_ * s_projectPrice;
        s_projectSupply -= amountToBuy_;
        s_collectedAmount += amountMainCurrency;
        s_tokensPurchased[msg.sender] += amountToBuy_;
        require(mainCurrency.transferFrom(msg.sender, address(this), amountMainCurrency), "Launchpad: Failed transfering MainCurrency");
        return true;
    }

    /*
        claimTokens() 
        * 1. require the round is over
        * 2. get the amount of the user
        * 3. require the user has bough tokens, otherwise revert
        * 4. transfer the amount to the user
    */

    function claimTokens() external nonReentrant {
        require(s_isActive, "Launchpad: Please wait until the round is over");
        uint256 amountPurchasedByUser = s_tokensPurchased[msg.sender];
        require(amountPurchasedByUser > 0, "Launchpad: You did not purchase tokens");
        require(projectToken.transfer(msg.sender, amountPurchasedByUser), "Launchpad: Failed transfering projectToken to the user");
    } 

    function changePrice(uint newPrice_) external onlyOwner{
        s_projectPrice = newPrice_;
    }

    function pauseOrStartRound() external onlyOwner{
        s_isActive = !s_isActive;
    }

    function setMinimumAmountToPurchase(uint256 amount_) external onlyOwner{
        s_minimumAmountToPurchase = amount_;
    }


}