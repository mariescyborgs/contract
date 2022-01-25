// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/PullPayment.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract MariesCyborgs is ERC721Enumerable, Ownable, PullPayment {
    using Strings for uint256;

    string public baseURI;
    string public baseExtension = ".json";

    //Price
    uint256 public publicCost = 400 ether;
    uint256 public EbisusbayMemberPrice = 350 ether;
    uint256 public whiteListCost = 300 ether;

    //Restrictions
    uint256 public maxSupply = 2500;
    uint256 public maxMintAmount = 25;
    uint256 public nftPerAddressLimit = 50;

    //Ebisusbay FEE : 5%
    uint256 public ebisusbayFee = 5;
    // EbisusbayWallet
    address public ebisusbayWallet = 0x454cfAa623A629CC0b4017aEb85d54C42e91479d;
    address public memberShipAddress =
        0x3F1590A5984C89e6d5831bFB76788F3517Cdf034;

    bool public paused = false;
    bool public onlyWhitelisted = false;

    //Struct with all Infos
    struct Infos {
        uint256 regularCost;
        uint256 memberCost;
        uint256 whitelistCost;
        uint256 maxSupply;
        uint256 totalSupply;
        uint256 maxMintPerAddress;
        uint256 maxMintPerTx;
    }

    // Infos[] public infosArr;

    mapping(address => uint256) public addressMintedBalance;
    mapping(address => bool) public whitelistedAddresses;

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initBaseURI
    ) ERC721(_name, _symbol) {
        setBaseURI(_initBaseURI);
    }

    function getInfos() public view returns (Infos memory) {
        Infos memory allInfos;
        allInfos.regularCost = publicCost;
        allInfos.memberCost = EbisusbayMemberPrice;
        allInfos.whitelistCost = whiteListCost;
        allInfos.maxSupply = maxSupply;
        allInfos.totalSupply = totalSupply();
        allInfos.maxMintPerAddress = nftPerAddressLimit;
        allInfos.maxMintPerTx = maxMintAmount;

        return allInfos;
    }

    // internal
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    // Mint Function for White-List and Public Sale
    event MintEvent(address indexed _from, uint256 indexed mintAmount);

    function mint(uint256 _mintAmount) public payable {
        require(!paused, "the contract is paused");
        uint256 supply = totalSupply();
        require(_mintAmount > 0, "need to mint at least 1 NFT");
        require(
            _mintAmount <= maxMintAmount,
            "max mint amount per session exceeded"
        );
        require((supply + _mintAmount) <= maxSupply, "max NFT limit exceeded");

        if (msg.sender != owner()) {
            if (onlyWhitelisted == true) {
                require(verifyUser(msg.sender), "user is not whitelisted");
            }

            uint256 ownerMintedCount = addressMintedBalance[msg.sender];
            require(
                (ownerMintedCount + _mintAmount) <= nftPerAddressLimit,
                "max NFT per address exceeded"
            );

            if (verifyUser(msg.sender)) {
                require(msg.value >= whiteListCost, "insufficient funds");
                require(_mintAmount == 1, "only 1 for White-List");
                addressMintedBalance[msg.sender]++;
                _safeMint(msg.sender, supply + 1);
                whitelistedAddresses[msg.sender] = false;
            } else {
                uint256 amountFee;
                if (isEbisusBayMember(msg.sender)) {
                    require(
                        msg.value >= (EbisusbayMemberPrice * _mintAmount),
                        "insufficient funds"
                    );
                    amountFee =
                        ((EbisusbayMemberPrice * _mintAmount) * ebisusbayFee) /
                        100;
                } else {
                    require(
                        msg.value >= (publicCost * _mintAmount),
                        "insufficient funds"
                    );
                    amountFee =
                        ((publicCost * _mintAmount) * ebisusbayFee) /
                        100;
                }

                for (uint256 i = 1; i <= _mintAmount; i++) {
                    addressMintedBalance[msg.sender]++;
                    _safeMint(msg.sender, supply + i);
                }
                _asyncTransfer(ebisusbayWallet, amountFee);
            }
        } else {
            for (uint256 i = 1; i <= _mintAmount; i++) {
                addressMintedBalance[msg.sender]++;
                _safeMint(msg.sender, supply + i);
            }
        }

        emit MintEvent(msg.sender, _mintAmount);
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        require(_owner != address(0), "not address 0");
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                )
                : "";
    }

    function setBaseURI(string memory _newBaseURI) public onlyOwner {
        baseURI = _newBaseURI;
    }

    function setBaseExtension(string memory _newBaseExtension)
        public
        onlyOwner
    {
        baseExtension = _newBaseExtension;
    }

    function pause(bool _state) public onlyOwner {
        paused = _state;
    }

    function withdraw() public payable onlyOwner {
        (bool os, ) = payable(owner()).call{value: address(this).balance}("");
        require(os);
    }

    // White List

    function setAllowList(address[] calldata addresses) public onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "Invalid address");
            whitelistedAddresses[addresses[i]] = true;
        }
    }

    function verifyUser(address _whitelistedAddress)
        public
        view
        returns (bool)
    {
        require(_whitelistedAddress != address(0), "not address 0");
        return whitelistedAddresses[_whitelistedAddress];
    }

    function setOnlyWhitelisted(bool _state) public onlyOwner {
        onlyWhitelisted = _state;
    }

    // End of White List;

    function getBalance() public view onlyOwner returns (uint256) {
        return address(this).balance;
    }

    // Ebisusbay Member

    function isEbisusBayMember(address _address) public view returns (bool) {
        ERC1155 memberships = ERC1155(memberShipAddress);
        return
            memberships.balanceOf(_address, 1) > 0 ||
            memberships.balanceOf(_address, 2) > 0;
    }

    function setMemberShipAddress(address _address) public onlyOwner {
        memberShipAddress = _address;
    }

    //Get NFT Cost
    function cost(address _address) public view returns (uint256) {
        require(_address != address(0), "not address 0");
        if (verifyUser(_address)) {
            return whiteListCost;
        }

        if (isEbisusBayMember(_address)) {
            return EbisusbayMemberPrice;
        }

        return publicCost;
    }
}
