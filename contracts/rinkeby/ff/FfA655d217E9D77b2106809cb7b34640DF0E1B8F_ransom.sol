pragma solidity ^0.8.0;

import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/token/ERC721/IERC721.sol";


interface iRansom {
    function getDogeOwner(uint256 tokenId) external returns(address);



}

contract ransom {

    event newNap(address napper, address nappee, uint256 doge, uint256 price, uint256 blockstamp);

    event dogeNapped(uint256 id,address napper, address nappee, uint256 tokenId, uint256 askingPrice, uint256 blockstamp);
    event dogeCaught(uint256 id,address napper, uint256 tokenId,uint256 blockstamp);
    event dogeSaved(uint256 id,address nappee, uint256 tokenId, uint256 askingPrice, uint256 blockstamp);

    address public Owner = msg.sender;
    address public addy;
    address payable store;
    address payable nappee;
     address payable c;
     uint256 napFee = 0.01 ether;
     uint256 captureFee = 0.01 ether;
     

    modifier onlyOwner(){
        require(msg.sender == Owner);
        _;
    }
 
 struct nap{

     uint256 id;
     address payable napper;
     address payable nappee;
     uint256 tokenId;
     uint256 askingFee;
     uint256 blockstamp;
     bool isNapping;
     bool isCaptured;
     bool isSaved;

 }

 

 nap[] public itemsForRescue;

 mapping(address => mapping (uint256 => bool)) activeItems;

 

 mapping(uint256 => nap) napIndex;

 mapping(address =>  uint256 [])  userGames;

 modifier HasTransferApproval(uint256 tokenId){
        IERC721 tokenContract = IERC721(addy);
        require(tokenContract.getApproved(tokenId) == address(this));
        _;
    }

    modifier ItemExists(uint256 tokenId) {
        require(tokenId < itemsForRescue.length && itemsForRescue[tokenId].tokenId == tokenId, "Could not find item");
        _;
    }

    modifier IsNotCaptured(uint256 tokenId) {
        require(itemsForRescue[tokenId].isNapping == true, "item is already sold");
        _;
    }

  
 function NapIt(address payable addr, uint256 tokenId, uint256 fee) public payable HasTransferApproval(tokenId) returns(uint256){

      address payable napper  = addr;
       
        c =  payable(iRansom(addy).getDogeOwner(tokenId));

       //return c;

        nappee = c;


        require (msg.value >= napFee, "there is a listing fee of 0.001 ether");
         require(activeItems[addy][tokenId]== false, "item is aready up for sale");
         uint256 newItemId = itemsForRescue.length;
         itemsForRescue.push(nap(newItemId, napper, nappee, tokenId, fee, block.timestamp, true, false, false));
         activeItems[addy][tokenId] = true;
         assert(itemsForRescue[newItemId].id == newItemId);

         userGames[napper].push(newItemId);
         userGames[nappee].push(newItemId);
         

         //IERC721(addy).safeTransferFrom(nappee, store, tokenId);
        IERC721(addy).transferFrom(iRansom(addy).getDogeOwner(tokenId), store, tokenId);
         emit dogeNapped(newItemId, napper, nappee, tokenId, fee, block.timestamp);
         return newItemId;

         


    


 }


 function SaveDoge (uint256 id) public payable {

        

        address cd = msg.sender;
        uint256 tokenId = itemsForRescue[id].tokenId;

       require (itemsForRescue[id].isNapping = true);
        require (cd == itemsForRescue[id].nappee);

        require (msg.value >= itemsForRescue[id].askingFee);

        

        IERC721(addy).transferFrom(store, itemsForRescue[id].nappee, tokenId);
       payable(itemsForRescue[id].napper).transfer(msg.value);
       itemsForRescue[id].isNapping = false;
       itemsForRescue[id].isCaptured = false;
       itemsForRescue[id].isSaved = true;
       emit dogeSaved(id, itemsForRescue[id].nappee, tokenId, itemsForRescue[id].askingFee,  block.timestamp);


    }

   

  function CaptureDoge (uint256 id) public payable {

        //uint256 captureFee = 0.01 ether;

        address cd = msg.sender;
        uint256 tokenId = itemsForRescue[id].tokenId;

        uint256 time = itemsForRescue[id].blockstamp;
        uint256 deathtime = block.timestamp - time;

        require (deathtime > 761);

       require (itemsForRescue[id].isNapping = true);
        require (cd == itemsForRescue[id].napper);


        require (msg.value >= captureFee);

        

        IERC721(addy).transferFrom(store, itemsForRescue[id].napper, tokenId);
       payable(itemsForRescue[id].nappee).transfer(msg.value);
       itemsForRescue[id].isNapping = false;
       itemsForRescue[id].isCaptured = true;
       itemsForRescue[id].isSaved = false;

       emit dogeCaught(id, itemsForRescue[id].napper, tokenId,  block.timestamp);


    }

   





  
  

  function setAddy(address _addy)public onlyOwner returns(address){
           addy = _addy;
           return addy;


   }

   function setStore(address payable _addy)public onlyOwner returns(address){
           store = _addy;
           return store;


   }

   function get_nap_info(uint256 _index) external view returns(uint256 _i, address napper, address nappee, uint256 tokenId, uint256 price, uint256 blockstamp) {
       
        nap memory napped = napIndex[_index];
        return (_index, napped.napper, napped.nappee, napped.tokenId, napped.askingFee, block.timestamp);

       
    }

    
    function withdraw() public payable onlyOwner{
       require (payable(msg.sender).send(address(this).balance));
   }

  function getUserGames(address user) public view returns(uint256 [] memory){

      uint[] memory result = userGames[user];
      
      return result;
  }

  function getActiveGames(address user) public view returns(uint256 [] memory){

      uint[] memory games = userGames[user];

      uint256 totalGames = games.length;

      if(totalGames == 0) {
            return new uint256[](0);
        }
        else{
            uint[] memory result = new uint256[](totalGames);
            uint256 resultIndex = 0;
            uint256 i;
            

            for(i = 0; i < totalGames; i++ ){
                if(itemsForRescue[i].isNapping == true){
                    result[resultIndex] = i;
                    resultIndex++;
                }
            }
            return result;
        }
  }

   
   

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
        return msg.data;
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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

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
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
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
    constructor() {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "evmVersion": "istanbul",
  "libraries": {},
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}