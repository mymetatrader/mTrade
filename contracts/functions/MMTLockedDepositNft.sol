// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "../interfaces/ITokenLockedDepositNftDesign.sol";

contract MMTLockedDepositNft is ERC721Enumerable {
    address public immutable mToken;
    ITokenLockedDepositNftDesign public design;

    uint8 public designDecimals;

    event DesignUpdated(ITokenLockedDepositNftDesign newValue);
    event DesignDecimalsUpdated(uint8 newValue);

    constructor(
        string memory name,
        string memory symbol,
        address _mToken,
        ITokenLockedDepositNftDesign _design,
        uint8 _designDecimals
    ) ERC721(name, symbol) {
        mToken = _mToken;
        design = _design;
        designDecimals = _designDecimals;
    }

    modifier onlyMToken() {
        require(msg.sender == mToken, "ONLY_GTOKEN");
        _;
    }

    modifier onlyMTokenManager() {
        require(msg.sender == IVault(mToken).manager(), "ONLY_MANAGER");
        _;
    }

    function updateDesign(ITokenLockedDepositNftDesign newValue)
        external
        onlyMTokenManager
    {
        design = newValue;
        emit DesignUpdated(newValue);
    }

    function updateDesignDecimals(uint8 newValue) external onlyMTokenManager {
        designDecimals = newValue;
        emit DesignDecimalsUpdated(newValue);
    }

    function mint(address to, uint256 tokenId) external onlyMToken {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyMToken {
        _burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        _requireMinted(tokenId);

        return
            design.buildTokenURI(
                tokenId,
                IVault(mToken).getLockedDeposit(tokenId),
                IERC20Metadata(mToken).symbol(),
                IERC20Metadata(IERC4626(mToken).asset()).symbol(),
                IERC20Metadata(mToken).decimals(),
                designDecimals
            );
    }
}
