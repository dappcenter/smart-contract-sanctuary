// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./BeastNFT.sol";
import "./ArenaNFT.sol";
import "./Random.sol";
import "./GenNFT.sol";

interface IGenNFT is IERC721 {
    function createToken(address holder, uint typeId) external;
}

contract Arena is Ownable, ERC721Holder {
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    using Random for Random.Seed;
    
    
    struct FighterInfo {
        address user;
        uint seed1;
        uint8 health1;
        uint8 strength1;
        uint8 defence1;
        uint seed2;
        uint8 health2;
        uint8 strength2;
        uint8 defence2;
        uint seed3;
        uint8 health3;
        uint8 strength3;
        uint8 defence3;
        uint coins;
        uint name;
        uint8 fights;
        uint16 currentAction;
        bool isSleep;
        uint16 place;
        uint[5] potions;
    }
    
    struct Log {
        address attacker;
        uint8 healthA1;
        uint8 healthA2;
        uint8 healthA3;
        address defender;
        uint8 healthD1;
        uint8 healthD2;
        uint8 healthD3;
        uint16[] kicks; // array 6 numbers ([damage] [enemyIndex] [myIndex])
        uint money;
        bool win;
        uint cycleIndex;
        uint roundIndex;
    }
    
    struct PotionLog {
       uint cycleIndex;
       uint potion;
       address target;
       address sender;
       uint roundIndex;
    }
    
    struct Place {
        address user;
        uint place;
    }
    
    enum State { IDLE, PREPARING, STARTED }
    
    
    BeastNFT public nft;
    ArenaNFT public arenaNft;
    IERC20 public gen;
    GenNFT public genNFT;
    IERC20 public usdc;
    uint8 public maxTeam = 3;
    
    
    uint public minLevel = 1;
    uint public maxLevel = 8;
    uint public neededFightAmount = 1;
    
    
    event Fight(Log log);
    event Potion(PotionLog log);
    
    struct Cycle {
        uint16 usersCount;
        uint16 deadAmount;
        
        mapping (address => uint[3]) teams;
        mapping (uint => uint8) health;
        mapping (uint => uint8) strength;
        mapping (uint => uint8) defence;
        mapping (address => uint8) fightNumber; 
        mapping (address => uint) money; 
        mapping (address => uint16) fightersIndexer;
        mapping (uint16 => address) allFighters;
        mapping (address => uint16) places;
        
        mapping (address => uint[5]) potions;
        
        mapping (address => mapping (uint => uint16)) rounds;
        //1 - attack
    }
     
    mapping (uint => Cycle) public cyclies;
    uint public startBlock = 0;
    
    
    
    uint16 public usersLimit = 6;  
    uint16 public roundTime = 25 * 2; // 2 min for round
    
    
    // uint public winMoney = 200 * 1e6;
    // uint public preparingTime = 40 * 25;//mins
    // uint public fightingTime = 40 * 25;//mins
    // uint public cycleTime = 7 * 24 * 60 * 25;//mins
    // uint16 public winnersAmount = 1;
    
        
    uint16 public winnersAmount = 1;
    uint public preparingTime = 5 * 25;//mins
    uint public fightingTime = 10 * 25;//mins
    uint public cycleTime = 16 * 25;//mins
    uint public winMoney = 0 * 1e6;
    
    constructor() {
        nft = BeastNFT(0xBD5be1F746cb21B90bc5B13f2C8CedAcB38a9b15);
        gen = IERC20(0x3eCdeB8fC5023839B92b0c293D049D61069e02b1);
        
        genNFT = GenNFT(0x330b06C695CfBb51D0cf9D5ed3debA2BD7eFFfB4);
        usdc = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
        arenaNft = ArenaNFT(0xf3041f58f7c7dEE9B146b4D8b8D4FB0c31c7ac82);
        start(10);
    }
    
    function startAt(uint block) public onlyOwner {
        require(startBlock == 0, "started already");   
        startBlock = block - fightingTime - preparingTime;
    }
    
    function start(uint blocksBeforePreparing) public onlyOwner {
        require(startBlock == 0, "started already");   
        startBlock = block.number - cycleTime + fightingTime + blocksBeforePreparing + preparingTime;
    }
    
    function getPlaces(uint cycleIndex) public view returns (uint16[] memory) {
        Cycle storage cycle = cyclies[cycleIndex];
        
        uint16[] memory places = new uint16[](30);
        for (uint16 i = 0; i < cycle.usersCount; i++) {
            places[i] = cycle.places[cycle.allFighters[i]];
        }
        return places;
    }
    
        
    function getPlaceFor(uint cycleIndex, address user) public view returns (uint16) {
        Cycle storage cycle = cyclies[cycleIndex];
        
        return cycle.places[user];
    }
    
    function getCycleIndex() public view returns (uint) {
        return (block.number - startBlock) / cycleTime;
    }
    
    function getRoundIndex() public view returns (uint) {
        uint time = (block.number - startBlock) % cycleTime;
        if (fightingTime <= cycleTime - time) {
            return 0;
        }
        return (fightingTime - (cycleTime - time)) / roundTime;
    }
    
    function getAction(uint roundIndex, address user) public view returns (uint) {
        return cyclies[getCycleIndex()].rounds[user][roundIndex];
    }
    
    mapping (address => mapping (uint => uint16)) rounds;
    
    function fight(address enemy) public {
        Cycle storage cycle = cyclies[getCycleIndex()];
        uint roundIndex = getRoundIndex();
        
        uint[3] memory myTeam = cycle.teams[msg.sender];
        uint[3] memory enemyTeam = cycle.teams[enemy];
        
        require(getState() == State.STARTED, "Battle didn't start");
        require(cycle.rounds[msg.sender][roundIndex] == 0, "Already made round");
        require(totalHealth(myTeam) > 0, "You have 0 health");
        
        require(totalHealth(enemyTeam) > 0,"Your enemy have 0 health");
        require(cycle.deadAmount + winnersAmount < cycle.usersCount, "battle is over");
        
        cycle.rounds[msg.sender][roundIndex] = 1;// attack round
        
        uint mySeed = uint(blockhash(block.number - 1)) / 100000;// >> 4 + userSeed >> 4 + ;
        uint enemySeed = mySeed / 10000000000;
        
        
        uint8 myDamage = 0;
        uint8 enemyDamage = 0;
        
        uint16[] memory kicks = new uint16[](6);
        
        for (uint8 i=0;i<3;i++) {
            if (cycle.health[myTeam[i]] > 0) {
                uint16 damage = attack(i,msg.sender,enemy, mySeed, 130, 0) * 10 + uint16(i);
                
                kicks[i * 2] = 10000 + damage;
                myDamage += uint8(damage / 100);
            } else {
                kicks[i * 2] = 0;
            }
            
            mySeed /= 1000;
                
            if (getRoundIndex() > 0 && cycle.rounds[enemy][getRoundIndex()] == 0) {
            
            } else if (cycle.health[enemyTeam[i]] > 0) {
                uint16 damage = attack(i,enemy,msg.sender, enemySeed, 100, 0) * 10 + uint16(i);
                
                kicks[i * 2 + 1] = 10000 + damage;
                enemyDamage += uint8(damage / 100);
            }
            
            enemySeed /= 1000;
        }
        
        cycle.fightNumber[msg.sender]++;
        
        fightFinished(enemy, myDamage, enemyDamage, kicks);
    }
    
    function attack(uint8 index, address me, address enemy, uint mySeed, uint damageMultiplier, uint enemyDefence) private returns (uint16) {//([damage] [enemyIndex])
        Cycle storage cycle = cyclies[getCycleIndex()];
        
        uint myId = cycle.teams[me][index];
        
        uint8 damage = 0;
      
            uint8 enemyIndex = index;
            
            if (cycle.health[cycle.teams[enemy][enemyIndex]] == 0) {
                for (uint8 i = 0; i<3; i++) {
                    if (cycle.health[cycle.teams[enemy][i]] > 0) {
                        enemyIndex = i;
                        break;
                    }
                }
            }
                
            uint enemyId = cycle.teams[enemy][enemyIndex];
            
            uint8 enemyHealth = cycle.health[enemyId];
            if (enemyHealth > 0) {
                if (mySeed % 10 >= cycle.defence[enemyId] + enemyDefence) { //try block
                    damage = uint8(((mySeed % 1000) % ((cycle.strength[myId]) + 1) * damageMultiplier / 100));
                    
                    if (enemyHealth > damage) {
                        cycle.health[enemyId] = enemyHealth - damage;
                    } else {
                        cycle.health[enemyId] = 0;
                        nft.kill(enemyId);
                    }
                }
            }
  
        return damage * 10 + enemyIndex;
    }
    
    function fightFinished(address enemy, uint8 myDamage, uint8 enemyDamage, uint16[] memory kicks) private {
        Cycle storage cycle = cyclies[getCycleIndex()];
        
        uint[3] memory myTeam = cycle.teams[msg.sender];
        uint[3] memory enemyTeam = cycle.teams[enemy];
        
        bool meAlive = totalHealth(myTeam) > 0;
        bool enemyAlive = totalHealth(enemyTeam) > 0;
        bool isWin = false;
        if (meAlive) {
            if ((myDamage >= enemyDamage) || (enemyAlive == false)) {
                isWin = true;
            }
        } else {
            cycle.deadAmount += 1;
            cycle.places[msg.sender] = (cycle.usersCount - cycle.deadAmount);
        }
        
        if (enemyAlive == false) {
            cycle.deadAmount += 1;
            cycle.places[enemy] = (cycle.usersCount - cycle.deadAmount);
        }

        emit Fight(Log(msg.sender,
        cycle.health[myTeam[0]],
        cycle.health[myTeam[1]],
        cycle.health[myTeam[2]],
        enemy,
        cycle.health[enemyTeam[0]],
        cycle.health[enemyTeam[1]],
        cycle.health[enemyTeam[2]],
        kicks, 0, isWin, getCycleIndex(), getRoundIndex()));
    }
    
    function totalHealth(uint[3] memory team) view public returns (uint8) {
        Cycle storage cycle = cyclies[getCycleIndex()];
        return cycle.health[team[0]] +  cycle.health[team[1]] + cycle.health[team[2]];
    }
    
    function addMonsters2(uint nftId1, uint nftId2, uint nftId3, uint gNftId1, uint gNftId2, uint gNftId3) public {
        require(getState() == State.PREPARING,"Battle already started");
        
        require(nft.ownerOf(nftId1) == msg.sender, "you are not owner");
        require(nft.ownerOf(nftId2) == msg.sender, "you are not owner");
        require(nft.ownerOf(nftId3) == msg.sender, "you are not owner");
        
        Cycle storage cycle = cyclies[getCycleIndex()];
        
        require(cycle.usersCount < usersLimit, "users Limit");
        
        cycle.teams[msg.sender][0] = nftId1;
        cycle.teams[msg.sender][1] = nftId2;
        cycle.teams[msg.sender][2] = nftId3;
        
        
        BeastNFT.Stats memory stats1 = nft.statsFor(nftId1);
        BeastNFT.Stats memory stats2 = nft.statsFor(nftId2);
        BeastNFT.Stats memory stats3 = nft.statsFor(nftId3);
        
        cycle.health[nftId1] = uint8(stats1.health);
        cycle.health[nftId2] = uint8(stats2.health);
        cycle.health[nftId3] = uint8(stats3.health);
        
        cycle.strength[nftId1] = uint8(stats1.strength);
        cycle.strength[nftId2] = uint8(stats2.strength);
        cycle.strength[nftId3] = uint8(stats3.strength);
        
        cycle.defence[nftId1] = uint8(stats1.defence);
        cycle.defence[nftId2] = uint8(stats2.defence);
        cycle.defence[nftId3] = uint8(stats3.defence);
        
        cycle.allFighters[cycle.usersCount] = msg.sender; 
        cycle.fightersIndexer[msg.sender] = cycle.usersCount;
        cycle.usersCount++;
        
        nft.safeTransferFrom(address(msg.sender), address(this), nftId1);
        nft.safeTransferFrom(address(msg.sender), address(this), nftId2);
        nft.safeTransferFrom(address(msg.sender), address(this), nftId3);
        
        require(genNFT.ownerOf(gNftId1) == msg.sender, "you are not owner");
        require(genNFT.ownerOf(gNftId2) == msg.sender, "you are not owner");
        require(genNFT.ownerOf(gNftId3) == msg.sender, "you are not owner");
        require(genNFT.getTypeByTokenId(gNftId1).id == 100, "wrong NFT");
        require(genNFT.getTypeByTokenId(gNftId2).id == 100, "wrong NFT");
        require(genNFT.getTypeByTokenId(gNftId3).id == 100, "wrong NFT");
        
        // genNFT.safeTransferFrom(address(msg.sender), address(this), gNftId1);
        // genNFT.safeTransferFrom(address(msg.sender), address(this), gNftId2);
        // genNFT.safeTransferFrom(address(msg.sender), address(this), gNftId3);
    }
    
    function revive(uint cycleIndex) public {
        Cycle storage cycle = cyclies[cycleIndex];
        for (uint8 i = 0; i< 3; i++) {
            uint id = cycle.teams[msg.sender][0];
            if (id > 0 && nft.isAlive(id) == false) {
                nft.revive(id);
                cycle.health[id] = 1;
            }
        }
            
        gen.transferFrom(msg.sender, address(this), 250 * 1e18);
    }
    
    function addPotions(uint[] memory nftIds, uint amount) public {
        Cycle storage cycle = cyclies[getCycleIndex()];
        
        require(getState() == State.PREPARING,"Battle already started");
        
        for (uint8 i = 0; i< amount; i++) {
            if (cycle.potions[msg.sender][i] == 0 && arenaNft.ownerOf(nftIds[i]) == msg.sender) {
                arenaNft.safeTransferFrom(address(msg.sender), address(this), nftIds[i]);
                cycle.potions[msg.sender][i] = nftIds[i];
            }
        }
    }
    
    function usePotion(uint8 index, address enemy) public {
        require(getState() == State.STARTED, "Battle didn't start");
        
        Cycle storage cycle = cyclies[getCycleIndex()];
        
        require(cycle.potions[msg.sender][index] != 0,"No potion to use");
        
        ArenaNFT.Type memory potionType = arenaNft.getTypeByTokenId(cycle.potions[msg.sender][index]);
        
        if (potionType.id == 1) {//heal
            for (uint8 i = 0; i< 3; i++) {
                uint id = cycle.teams[msg.sender][i];    
                if (nft.isAlive(id)) {
                    cycle.health[id] += uint8(potionType.bonus);
                }
            }
        } else {
            
            for (uint8 i = 0; i< 3; i++) {
                uint id = cycle.teams[enemy][i];      
              
                if (potionType.id == 2) {//fire
                    if (cycle.health[id] <= uint8(potionType.bonus)) {
                        cycle.health[id] = 0;
                        nft.kill(id);
                    } else {
                        cycle.health[id] -= uint8(potionType.bonus);
                    }
                } else 
                if (potionType.id == 3) {//poison lower defence
                    if (cycle.defence[id] <= uint8(potionType.bonus)) {
                        cycle.defence[id] = 0;
                    } else {
                        cycle.defence[id] -= uint8(potionType.bonus);
                    }
                } else 
                if (potionType.id == 4) {//weakness lower strength
                    if (cycle.strength[id] <= uint8(potionType.bonus)) {
                        cycle.strength[id] = 0;
                    } else {
                        cycle.strength[id] -= uint8(potionType.bonus);
                    }
                }
            }
        }

        emit Potion(PotionLog(getCycleIndex(), potionType.id, enemy, msg.sender, getRoundIndex()));
        cycle.rounds[msg.sender][getRoundIndex()] = uint16(10 + potionType.id);
        cycle.potions[msg.sender][index] = 0;
    }
    
    
    function leave(uint cycleIndex) public {
        Cycle storage cycle = cyclies[cycleIndex];
        
        uint id0 = cycle.teams[msg.sender][0];
        uint id1 = cycle.teams[msg.sender][1];
        uint id2 = cycle.teams[msg.sender][2];
        
        require(cycleIndex < getCycleIndex(), "Battle not finished");
        require(id0 + id1 + id2 > 0, "already claimed");
        
        if (id0 > 0 && nft.isAlive(id0)) {
            nft.addEvolvePoint(id0,cycle.fightNumber[msg.sender]);
            nft.safeTransferFrom(address(this), address(msg.sender), id0);
        }
        
        if (id1 > 0 && nft.isAlive(id1)) {
            nft.addEvolvePoint(id1,cycle.fightNumber[msg.sender]);
            nft.safeTransferFrom(address(this), address(msg.sender), id1);
        }
        
        if (id2 > 0 && nft.isAlive(id2)) {
            nft.addEvolvePoint(id2,cycle.fightNumber[msg.sender]);
            nft.safeTransferFrom(address(this), address(msg.sender), id2);
        }
        
        
         if (cycle.deadAmount + winnersAmount >= cycle.usersCount) {
            if (cycle.places[msg.sender] == 0) { 
                usdc.safeTransfer(address(msg.sender), winMoney);
            } else  {
                if (cycle.places[msg.sender] == 1) {
                    genNFT.createToken(msg.sender, 5);
                } else if (cycle.places[msg.sender] == 2) {
                    genNFT.createToken(msg.sender, 4);
                } else if (cycle.places[msg.sender] == 3) {
                    genNFT.createToken(msg.sender, 3);
                } else if (cycle.places[msg.sender] == 4) {
                    genNFT.createToken(msg.sender, 2);
                }
                
            }
        }
        
        for (uint8 i = 0; i < 5; i++) {
            if (cycle.potions[msg.sender][i] != 0) {
                arenaNft.safeTransferFrom( address(this),address(msg.sender), cycle.potions[msg.sender][i]);
                cycle.potions[msg.sender][i] = 0;
            }
        }
        
        
        cycle.teams[msg.sender][0] = 0;
        cycle.teams[msg.sender][1] = 0;
        cycle.teams[msg.sender][2] = 0;
        
        
    }
    
    function getState() public view returns (State) {
        uint time = (block.number - startBlock) % cycleTime;
        uint idleTime = cycleTime - preparingTime - fightingTime;
        if (time < idleTime) return State.IDLE;
        if (time < preparingTime + idleTime) return State.PREPARING;
        return State.STARTED;
    }
    
    function withdrawAll() external onlyOwner {
        usdc.safeTransfer(msg.sender, usdc.balanceOf(address(this)));
    }
    
    
    function getFightersInfo(uint cycleIndex) view external returns (FighterInfo[] memory) {
        Cycle storage cycle = cyclies[cycleIndex];
        FighterInfo[] memory info = new FighterInfo[](cycle.usersCount);
        
        for (uint16 i=0;i<cycle.usersCount; i++) {
            info[i] = getFighterInfo(cycle.allFighters[i], cycleIndex);
        }
        
        return info;
    }
    
    function getFighterInfo(address user, uint cycleIndex) view public returns (FighterInfo memory) {
        Cycle storage cycle = cyclies[cycleIndex];
        uint[3] memory team = cycle.teams[user];
        
        uint roundIndex = getRoundIndex();
        return FighterInfo(user,
            nft.valuesSeedFor(team[0]),
            cycle.health[team[0]],
            cycle.strength[team[0]],
            cycle.defence[team[0]],
            nft.valuesSeedFor(team[1]),
            cycle.health[team[1]],
            cycle.strength[team[1]],
            cycle.defence[team[1]],
            nft.valuesSeedFor(team[2]),
            cycle.health[team[2]],
            cycle.strength[team[2]],
            cycle.defence[team[2]],
            cycle.money[user],
            cycle.fightersIndexer[user],
            cycle.fightNumber[user],
            cycle.rounds[user][roundIndex],
            (roundIndex > 0 && cycle.rounds[user][roundIndex - 1] == 0),
            cycle.places[user],
            cycle.potions[user]
            );
    }
    
    function updateMinMax(uint min, uint max, uint money) public onlyOwner {
        minLevel = min;
        maxLevel = max;
        winMoney = money * 1e6;
    }
    
    function updateUsersLimit(uint16 limit) public onlyOwner {
        usersLimit = limit;
    }
    
    function updateNeededFightAmount(uint amount) public onlyOwner {
        neededFightAmount = amount;
    }
    
    //Trusted
    mapping(address=>bool) private _isTrusted;
    modifier onlyTrusted {
        require(_isTrusted[msg.sender] || msg.sender == owner(), "not trusted");
        _;
    }
    
    function addTrusted(address user) public onlyOwner {
        _isTrusted[user] = true;
    }
    
    function removeTrusted(address user) public onlyOwner {
        _isTrusted[user] = false;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overloaded;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721Receiver.sol";

  /**
   * @dev Implementation of the {IERC721Receiver} interface.
   *
   * Accepts all token transfers.
   * Make sure the contract is able to use its token with {IERC721-safeTransferFrom}, {IERC721-approve} or {IERC721-setApprovalForAll}.
   */
contract ERC721Holder is IERC721Receiver {

    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
      * @dev Safely transfers `tokenId` token from `from` to `to`.
      *
      * Requirements:
      *
      * - `from` cannot be the zero address.
      * - `to` cannot be the zero address.
      * - `tokenId` token must exist and be owned by `from`.
      * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
      * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
      *
      * Emits a {Transfer} event.
      */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract BeastNFT is ERC721Enumerable, Ownable  {

    //// different types of features
    struct Value {
        uint id;
        uint amount;   // how much boost
        uint param;  // what boost
    }

    struct Ability {
        uint feature; //body, horns, wings
        Value value;
    }

    struct Info {
        uint valuesSeed;
        uint abilitiesAmount;
        uint breedLeft;
        uint evolvePoints;
        bool dead;
    }

    struct Stats {
        uint health;  //1
        uint strength;//2
        uint defence;//3
    }

    constructor() ERC721("Beast NFT","BeastNFT") {

    }

    function addValueToFeature(uint featureId, uint id, uint value, uint param) public onlyOwner {
        if (featureId + 1 > featuresAmount) {
            featuresAmount = featureId + 1;
        }
        featureToValues[featureId].push(Value(id, value, param));
    }


    function updateBreedTimes(uint _maxBreedTimes) public onlyOwner {
        maxBreedTimes = _maxBreedTimes;
    }

    function updateEvolvePointsMultiplier(uint _evolvePointsMultiplier) public onlyOwner {
        evolvePointsMultiplier = _evolvePointsMultiplier;
    }

    uint public featuresAmount;
    uint public maxBreedTimes = 3;
    uint public evolvePointsMultiplier = 10;

    mapping (uint=>Value[]) public featureToValues;

    mapping (uint=>uint) public valuesSeedByTokenId;
    mapping (uint=>uint) public abilitiesAmountByTokenId;

    mapping (uint=>uint) public breedAmount;

    mapping (uint=>uint) public evolvePoints;
    mapping (uint=>bool) public dead;

    using EnumerableSet for EnumerableSet.UintSet;
    using Strings for uint256;

       //Trusted
    mapping(address=>bool) public _isTrusted;
    modifier onlyTrusted {
        require(_isTrusted[msg.sender] || msg.sender == owner(), "not trusted");
        _;
    }

    function addTrusted(address user) public onlyOwner {
        _isTrusted[user] = true;
    }

    function removeTrusted(address user) public onlyOwner {
        _isTrusted[user] = false;
    }

    uint nextTokenId = 0;

    function createToken(address holder) public onlyTrusted returns (uint tokenId) {
        tokenId = ++nextTokenId;
        _mint(holder, tokenId);
    }

    function updateAbilities(uint tokenId, uint amount, uint valuesSeed) public onlyTrusted {
        abilitiesAmountByTokenId[tokenId] = amount;
        valuesSeedByTokenId[tokenId] = valuesSeed;
    }

    function addEvolvePoint(uint tokenId, uint points) public onlyTrusted {
        evolvePoints[tokenId] += points;
    }

    function evolve(uint tokenId) public onlyTrusted {
        require(evolvePoints[tokenId] >= abilitiesAmountByTokenId[tokenId] * evolvePointsMultiplier / 10, "can't evolve");
        require(abilitiesAmountByTokenId[tokenId] < featuresAmount, "can't evolve");
        evolvePoints[tokenId] -= abilitiesAmountByTokenId[tokenId] * evolvePointsMultiplier / 10;
    }

    function kill(uint tokenId) public onlyTrusted {
        dead[tokenId] = true;
    }

    function revive(uint tokenId) public onlyTrusted {
        dead[tokenId] = false;
    }

    function breed(uint tokenId) public onlyTrusted {
        breedAmount[tokenId] = breedAmount[tokenId] + 1;
        if (breedAmount[tokenId] >= maxBreedTimes) {
            dead[tokenId] = true;
        }
    }

    function isAlive(uint tokenId) view public returns (bool) {
        return dead[tokenId] == false;
    }

     function canEvolve(uint tokenId) view public returns (bool) {
        return (dead[tokenId] == false) &&
        (abilitiesAmountByTokenId[tokenId] < featuresAmount) &&
        (abilitiesAmountByTokenId[tokenId] * evolvePointsMultiplier / 10 <= evolvePoints[tokenId]);
    }

    function valuesSeedFor(uint tokenId) view public returns (uint) {
        return valuesSeedByTokenId[tokenId];
    }

    function abilitiesAmount(uint tokenId) view public returns (uint) {
        return abilitiesAmountByTokenId[tokenId];
    }

    function valuesAmountFor(uint feature) view public returns (uint) {
        return featureToValues[feature].length;
    }

    function info(uint tokenId) view public returns (Info memory) {
        return Info(valuesSeedByTokenId[tokenId],
        abilitiesAmountByTokenId[tokenId],
        maxBreedTimes - breedAmount[tokenId],
        evolvePoints[tokenId],
        dead[tokenId]);
    }

    function statsFor(uint tokenId) view public returns (Stats memory) {//health,strength,defence
        Ability[] memory abilities = abilitiesFor(tokenId);
        uint[] memory stats = new uint[](4);
        for (uint i = 0; i< abilities.length; i++) {
            stats[abilities[i].value.param] += abilities[i].value.amount;
        }
        if (dead[tokenId] == true) {
            stats[1] = 0;
        }
        return Stats(stats[1],stats[2] + 5,stats[3]);
    }

    function abilitiesFor(uint tokenId) view public returns (Ability[] memory) {

        uint abilAmount = abilitiesAmountByTokenId[tokenId];
        uint valuesSeed = valuesSeedByTokenId[tokenId];

        Ability[] memory abilities = new Ability[](abilAmount);

        for (uint featureIndex = 0; featureIndex < abilAmount; featureIndex++) {

            uint valueNumber = valuesSeed % 1000;

            abilities[featureIndex] = Ability(featureIndex, featureToValues[featureIndex][valueNumber - 1]);

            valuesSeed /= 1000;
        }

        return abilities;
    }

    function allfeatureToValues() view public returns (Value[][] memory) {
        Value[][] memory all = new Value[][](featuresAmount);

        for (uint i = 0; i< featuresAmount; i++) {
            all[i] = featureToValues[i];
        }

        return all;
    }


    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nft.evodefi.com/";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory baseURI = ERC721.tokenURI(tokenId);
        return string(abi.encodePacked(
            baseURI, "/", valuesSeedByTokenId[tokenId].toString()));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract ArenaNFT is ERC721Enumerable, Ownable  {

    using EnumerableSet for EnumerableSet.UintSet;
    using Strings for uint256;

    // Trusted
    mapping(address=>bool) public _isTrusted;
    modifier onlyTrusted {
        require(_isTrusted[msg.sender] || msg.sender == owner(), "not trusted");
        _;
    }

    function addTrusted(address user) public onlyOwner {
        _isTrusted[user] = true;
    }

    function removeTrusted(address user) public onlyOwner {
        _isTrusted[user] = false;
    }

    struct Type {
        uint id;
        uint bonus;
        uint rarity;
    }

    constructor() ERC721("Arena NFT","ArenaNFT") {}

    // Token.Type data
    EnumerableSet.UintSet typeIds;

    mapping (uint=>Type) typesById;
    mapping (uint=>EnumerableSet.UintSet) private typeIdsByRarity;
    mapping (uint=>uint) private mintIndexByTokenId;

    uint nextTokenId = 0;
    mapping (uint=>uint) private typeIdByTokenId;

    function createToken(address holder, uint typeId) public onlyTrusted returns (uint tokenId) {
        tokenId = ++nextTokenId;
        typeIdByTokenId[tokenId] = typeId;
        _mint(holder, tokenId);
    }

    function createRandomNFT(address holder, uint rarity, uint seed) public onlyTrusted returns (uint) {
        EnumerableSet.UintSet storage filter = typeIdsByRarity[rarity];
        require(filter.length() > 0, "there are no types with that rarity");
        uint typeId = filter.at(seed % filter.length());
        return createToken(holder, typeId);
    }

    function changeType(uint tokenId, uint toTypeId) public onlyTrusted {
        typeIdByTokenId[tokenId] = toTypeId;
    }

    function addType(uint id, uint bonus, uint rarity) public onlyOwner {
        require(!typeIds.contains(id), "id already exists");
        typeIds.add(id);
        typesById[id] = Type(id, bonus, rarity);
        typeIdsByRarity[rarity].add(id);
    }

    function removeType(uint id) public onlyOwner {
        require(typeIds.contains(id), "id does not exist");
        typeIds.remove(id);
        typeIdsByRarity[typesById[id].rarity].remove(id);
    }

    function replaceType(uint id, uint bonus, uint rarity) public onlyOwner {
        removeType(id);
        addType(id, bonus, rarity);
    }

    function getTypeById(uint id) public view returns (Type memory) { return typesById[id]; }

    function getTypeByTokenId(uint id) public view returns (Type memory) { return typesById[typeIdByTokenId[id]]; }

    function getTypeCount() public view returns (uint) {
        return typeIds.length();
    }

    function getTypeIdAtIndex(uint index) public view returns (uint) {
        return typeIds.at(index);
    }

    function getTypeAtIndex(uint index) public view returns (Type memory tokenType) {
        tokenType = typesById[typeIds.at(index)];
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nft.evodefi.com/";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory baseURI = ERC721.tokenURI(tokenId);
        Type memory tokenType = getTypeByTokenId(tokenId);
        return string(abi.encodePacked(baseURI, "/arena/", tokenType.id.toString()));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

library Random {

  struct Seed {
    uint blockNumber;
  }

  function isInitialized(Seed memory seed) internal pure returns (bool) {
    return seed.blockNumber > 0;
  }

  function isReady(Seed memory seed) internal view returns (bool) {
    return block.number > seed.blockNumber + 1;
  }

  function init(Seed storage seed) internal {
    require(!isInitialized(seed), "Seed already initialized");
    seed.blockNumber = block.number;
  }

  function get(Seed storage seed) internal view returns (bytes32) {
    require(isInitialized(seed), "Seed is not initialized");
    require(block.number > seed.blockNumber, "Wait one more block to open this Seed");
    return blockhash(seed.blockNumber + 1);
  }

  function reset(Seed storage seed) internal {
    seed.blockNumber = 0;
  }

}

// SPDX-License-Identifier: MIT
pragma solidity >=0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract GenNFT is ERC721Enumerable, Ownable  {

    using EnumerableSet for EnumerableSet.UintSet;
    using Strings for uint256;

    // Trusted
    mapping(address=>bool) public _isTrusted;
    modifier onlyTrusted {
        require(_isTrusted[msg.sender] || msg.sender == owner(), "not trusted");
        _;
    }

    function addTrusted(address user) public onlyOwner {
        _isTrusted[user] = true;
    }

    function removeTrusted(address user) public onlyOwner {
        _isTrusted[user] = false;
    }

    struct Type {
        uint id;
        uint bonus;
        uint rarity;
    }

    constructor() ERC721("Gen NFT","GenNFT") {}

    // Token.Type data
    EnumerableSet.UintSet typeIds;

    mapping (uint=>Type) typesById;
    mapping (uint=>EnumerableSet.UintSet) private typeIdsByRarity;
    mapping (uint=>uint) private mintIndexByTokenId;

    uint nextTokenId = 0;
    mapping (uint=>uint) private typeIdByTokenId;

    function createToken(address holder, uint typeId) public onlyTrusted returns (uint tokenId) {
        tokenId = ++nextTokenId;
        typeIdByTokenId[tokenId] = typeId;
        _mint(holder, tokenId);
    }

    function createRandomNFT(address holder, uint rarity, uint seed) public onlyTrusted returns (uint) {
        EnumerableSet.UintSet storage filter = typeIdsByRarity[rarity];
        require(filter.length() > 0, "there are no types with that rarity");
        uint typeId = filter.at(seed % filter.length());
        return createToken(holder, typeId);
    }

    function changeType(uint tokenId, uint toTypeId) public onlyTrusted {
        typeIdByTokenId[tokenId] = toTypeId;
    }

    function addType(uint id, uint bonus, uint rarity) public onlyOwner {
        require(!typeIds.contains(id), "id already exists");
        typeIds.add(id);
        typesById[id] = Type(id, bonus, rarity);
        typeIdsByRarity[rarity].add(id);
    }

    function removeType(uint id) public onlyOwner {
        require(typeIds.contains(id), "id does not exist");
        typeIds.remove(id);
        typeIdsByRarity[typesById[id].rarity].remove(id);
    }

    function replaceType(uint id, uint bonus, uint rarity) public onlyOwner {
        removeType(id);
        addType(id, bonus, rarity);
    }

    function getTypeById(uint id) public view returns (Type memory) { return typesById[id]; }

    function getTypeByTokenId(uint id) public view returns (Type memory) { return typesById[typeIdByTokenId[id]]; }

    function getTypeCount() public view returns (uint) {
        return typeIds.length();
    }

    function getTypeIdAtIndex(uint index) public view returns (uint) {
        return typeIds.at(index);
    }

    function getTypeAtIndex(uint index) public view returns (Type memory tokenType) {
        tokenType = typesById[typeIds.at(index)];
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return "https://nft.evodefi.com/";
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        string memory baseURI = ERC721.tokenURI(tokenId);
        Type memory tokenType = getTypeByTokenId(tokenId);
        return string(abi.encodePacked(
            baseURI, "/",
            tokenId.toString(), "/",
            tokenType.bonus.toString(), "/",
            tokenType.rarity.toString()));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC721.sol";
import "./IERC721Enumerable.sol";

/**
 * @dev This implements an optional extension of {ERC721} defined in the EIP that adds
 * enumerability of all the token ids in the contract as well as all token ids owned by each
 * account.
 */
abstract contract ERC721Enumerable is ERC721, IERC721Enumerable {
    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721.balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721Enumerable.totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = ERC721.balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "./extensions/IERC721Enumerable.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping (uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping (address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping (uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0
            ? string(abi.encodePacked(baseURI, tokenId.toString()))
            : '';
    }

    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(_msgSender() == owner || ERC721.isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || ERC721.isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
        private returns (bool)
    {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual { }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Enumerable is IERC721 {

    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {

    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant alphabet = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = alphabet[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "libraries": {}
}