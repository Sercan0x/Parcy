// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract Parcy {
    address public owner;
    IERC20 public token;

    struct Invoice {
        string id;
        bytes32 idHash;
        uint256 amount;
        address issuer;
        bool paid;
        address payer;
        uint256 paidAt;
        string description;
    }

    mapping(bytes32 => Invoice) public invoices;
    mapping(address => string) public creatorPrefix;

    event InvoiceCreated(bytes32 indexed idHash, string id, uint256 amount, address issuer);
    event InvoicePaid(bytes32 indexed idHash, string id, uint256 amount, address payer);  // ✅ FIX: indexed eklendi
    event InvoiceEdited(string oldId, string newId);
    event InvoiceDeleted(string id);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier canCreate(string calldata id) {
        if (msg.sender != owner) {
            string memory prefix = creatorPrefix[msg.sender];
            require(bytes(prefix).length != 0, "Not permitted");
            require(matchesPrefix(id, prefix), "Invalid prefix");
        }
        _;
    }

    constructor(address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    function setCreator(address creator, string calldata prefix) external onlyOwner {
        creatorPrefix[creator] = prefix;
    }

    function removeCreator(address creator) external onlyOwner {
        delete creatorPrefix[creator];
    }

    function createInvoice(
        string calldata id,
        uint256 amount,
        string calldata description
    ) external canCreate(id) {
        bytes32 h = keccak256(bytes(id));
        require(invoices[h].issuer == address(0), "Invoice exists");

        invoices[h] = Invoice(
            id,
            h,
            amount,
            msg.sender,
            false,
            address(0),
            0,
            description
        );

        emit InvoiceCreated(h, id, amount, msg.sender);
    }

    function getInvoice(string calldata id)
        external
        view
        returns (
            uint256 amount,
            address issuer,
            bool paid,
            address payer,
            uint256 paidAt,
            string memory description
        )
    {
        bytes32 h = keccak256(bytes(id));
        Invoice storage inv = invoices[h];
        return (inv.amount, inv.issuer, inv.paid, inv.payer, inv.paidAt, inv.description);
    }

    function editInvoice(
        string calldata oldId,
        string calldata newId,
        uint256 newAmount,
        string calldata newDescription
    ) external {
        bytes32 oldHash = keccak256(bytes(oldId));
        Invoice storage inv = invoices[oldHash];

        require(inv.issuer != address(0), "Not found");
        require(msg.sender == inv.issuer || msg.sender == owner, "Not authorized");
        require(!inv.paid, "Already paid");

        address savedIssuer = inv.issuer;  

        delete invoices[oldHash];

        bytes32 newHash = keccak256(bytes(newId));

        invoices[newHash] = Invoice(
            newId,
            newHash,
            newAmount,
            savedIssuer,  
            false,
            address(0),
            0,
            newDescription
        );

        emit InvoiceEdited(oldId, newId);
    }

    function deleteInvoice(string calldata id) external {
        bytes32 h = keccak256(bytes(id));
        Invoice storage inv = invoices[h];

        require(inv.issuer != address(0), "Not found");
        require(msg.sender == inv.issuer || msg.sender == owner, "Not authorized");
        require(!inv.paid, "Already paid");

        delete invoices[h];

        emit InvoiceDeleted(id);
    }

    function payInvoice(string calldata id) external {
        bytes32 h = keccak256(bytes(id));
        Invoice storage inv = invoices[h];

        require(inv.issuer != address(0), "Invoice not found");
        require(!inv.paid, "Already paid");

        uint256 fee = inv.amount / 100;

        require(token.transferFrom(msg.sender, inv.issuer, inv.amount), "Issuer transfer failed");
        require(token.transferFrom(msg.sender, owner, fee), "Fee transfer failed");

        inv.paid = true;
        inv.payer = msg.sender;
        inv.paidAt = block.timestamp;

        emit InvoicePaid(h, inv.id, inv.amount, msg.sender);
    }

    function getPrefix(address user) external view returns (string memory) {
        return creatorPrefix[user];
    }

    function matchesPrefix(string calldata input, string memory prefix)
        internal
        pure
        returns (bool)
    {
        bytes memory a = bytes(input);
        bytes memory b = bytes(prefix);
        if (b.length > a.length) return false;

        for (uint256 i = 0; i < b.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }
}
