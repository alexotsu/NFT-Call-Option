// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;
import "@oz/token/ERC721/IERC721Receiver.sol";
import "@oz/token/ERC721/IERC721.sol";
import "@oz/token/ERC20/IERC20.sol";
import "@oz/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IERC20Permit.sol";

// @notice this is quick and dirty edits from original as a proof of concept, the "right" way would probably be to make each option its own ERC-20 token so that they can be bought and sold on open market.

/**
 * @title NFT Call Option
 * @author verum
 */
contract Option is IERC721Receiver {
    using SafeERC20 for IERC20;
    /************************************************
     *  STORAGE
    ***********************************************/
    mapping (uint256 => Option) options;

    uint256 private optionNumber;

    /************************************************
     *  IMMUTABLES & CONSTANTS
    ***********************************************/

    struct Option {
        // flag whether NFT has been deposited to contract
        bool nftDeposited;

        /// @notice creator of the option
        address seller;

        /// @notice buyer of the option
        address buyer;

        /// @notice address of NFT contract
        address underlying;

        /// @notice index of the NFT 
        uint256 tokenId;

        /// @notice ERC20 (likely a stablecoin) in which the premium & strike is denominated
        address quoteToken;

        /// @notice strike price specified in underlyingDenomination
        uint256 strike;

        /// @notice premium specified in underlyingDenomination
        uint256 premium;

        ///@notice expiry of contract
        uint256 expiry;
    }

    struct PermitData {
        uint deadline; 
        uint8 v; 
        bytes32 r;
        bytes32 s;
    }

    /************************************************
     *  EVENTS, ERRORS, MODIFIERS
    ***********************************************/
    /// Emit when NFT is transferred to this contract
    event NftDeposited(address indexed from, address indexed underlying, uint256 tokenId);

    event OptionPurchased(address indexed buyer);

    event OptionExercised();

    modifier onlySeller {
        require(msg.sender == seller, "only seller");
        _;
    }

    /**
     * @notice Deposits the underlying NFT to this contract
     * @dev approve() should be called before invoking this function
     * @param _underlying - underlying NFT address
     * @param _tokenId - ID of the token that the sender owns 
     */
    function deposit(address _underlying, uint256 _tokenId, address _quoteToken, uint256 _strike, uint256 _premium, uint256 _expiry) external {
        // requires seller to have approved transfer of their ERC721
        // Assumes revert on failed transfer

        (bool success, ) = IERC721(_underlying).safeTransferFrom(msg.sender, address(this), _tokenId);
        require(success, 'Transfer failed');
        options[optionNumber] = Option(true, msg.sender. address(0), _underlying, _tokenId, _quoteToken, _strike, _premium, _expiry);
        optionNumber++;

        emit NftDeposited(msg.sender, _underlying, _tokenId);
    }

    /**
     * @notice purchases the call option 
     * @dev approve() should be called before invoking this function OR a permitSignature can be passed in 
     * @param _permitData - info for ERC20-Permit; can be empty byte if approve() was called
     */
    function purchaseCall(bytes calldata _permitData, uint256 _optionNumber) external {
        require(options[_optionNumber].buyer == address(0), "option has already been purchased");
        require(options[_optionNumber].nftDeposited, "No NFT has been deposited yet");
        require(block.timestamp <= options[_optionNumber].expiry, "Cannot purchase option after it has expired");

        if (_permitData.length > 0) {
            PermitData memory permitData = abi.decode(_permitData, (PermitData));
            IERC20Permit(options[_optionNumber].quoteToken).permit(
                msg.sender, address(this), premium, permitData.deadline, permitData.v, permitData.r, permitData.s
            );
        }

        // Transfer premium straight to seller
        IERC20(options[_optionNumber].quoteToken).safeTransferFrom(msg.sender, seller, premium);

        // Update state
        options[_optionNumber].buyer = msg.sender;
        emit OptionPurchased(msg.sender);
    }

    // @todo function sellCall() to allow holder of option to sell it to someone else, alternatively do suggestion at top of code and turn the whole thing into an ERC-20

    /**
     * @notice Allows the purchaser of the call option to buy underlying NFT
     * @dev approve() should be called before invoking this function OR a permitSignature can be passed in 
     * @param _permitData - info for ERC20-Permit; can be empty byte if approve() was called
     */
    function exerciseOption(bytes calldata _permitData, uint256 _optionNumber) external {
        require(msg.sender == buyer, "Only buyer can exercise option");
        require(block.timestamp <= expiry, "Option has expired");

        if (_permitData.length > 0) {
            PermitData memory permitData = abi.decode(_permitData, (PermitData));
            IERC20Permit(quoteToken).permit(
                msg.sender, address(this), strike, permitData.deadline, permitData.v, permitData.r, permitData.s
            );
        }

        // Transfer strike straight to seller
        IERC20(options[_optionNumber].quoteToken).safeTransferFrom(msg.sender, options[_optionNumber].seller, options[_optionNumber].strike);

        // Transfer underlying NFT to the buyer
        IERC721(underlying).safeTransferFrom(address(this), msg.sender, tokenId);

        emit OptionExercised();
    }

    /**
     * @notice Allows the seller to close the option & withdraw NFT if option is past expiry or there is no buyer 
     */
    function closeOption(uint256 _optionNumber) external {
        require(block.timestamp > options[_optionNumber].expiry || options[_optionNumber].buyer == address(0), "Option has not expired yet");
        require(msg.sender == options[_optionNumber].seller);
        // Transfer NFT back to seller
        IERC721(underlying).safeTransferFrom(address(this), msg.sender, tokenId);
        options[_optionNumber].nftDeposited = false;
    }

    /**
     * @inheritdoc IERC721Receiver
     */
    function onERC721Received(address, address, uint256, bytes memory) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
