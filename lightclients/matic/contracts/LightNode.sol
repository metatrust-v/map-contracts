// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interface/ILightNode.sol";
import "./lib/Verify.sol";

// import "hardhat/console.sol";

contract LightNode is UUPSUpgradeable, Initializable, Pausable, ILightNode {
    uint256 public constant EPOCH_NUM = 64;

    uint256 internal constant MAX_SAVED_EPOCH_NUM = 121500;

    uint256 internal constant ADDRESS_LENGTH = 20;

    address public mptVerify;

    uint256 public minValidBlocknum;

    uint256 public minEpochBlockExtraDataLen;

    mapping(uint256 => bytes) public validators;

    uint256 internal _lastSyncedBlock;

    uint256 public chainId;

    uint256 public confirms;

   address private _pendingAdmin;

    event ChangePendingAdmin(address indexed previousPending, address indexed newPending);
    event AdminTransferred(address indexed previous, address indexed newAdmin);

    struct ProofData {
        Verify.BlockHeader[] headers;
        Verify.ReceiptProof receiptProof;
    }

    modifier onlyOwner() {
        require(msg.sender == _getAdmin(), "lightnode :: only admin");
        _;
    }

    constructor() {}

    function initialize(
        uint256 _chainId,
        uint256 _minEpochBlockExtraDataLen,
        address _controller,
        address _mptVerify,
        uint256 _confirms,
        Verify.BlockHeader memory _header
    ) public initializer {
        require(_chainId > 0, "invalid _chainId");
        require(_confirms > 0, "invalid _confirms");
        require(minEpochBlockExtraDataLen == 0, "already initialized");
        require(_controller != address(0), "_controller zero address");
        require(_mptVerify != address(0), "_mptVerify zero address");
        chainId = _chainId;
        mptVerify = _mptVerify;
        confirms = _confirms;
        _changeAdmin(_controller);
        minEpochBlockExtraDataLen = _minEpochBlockExtraDataLen;
        _initBlock(_header);
    }

    function togglePause(bool _flag) public onlyOwner returns (bool) {
        if (_flag) {
            _pause();
        } else {
            _unpause();
        }

        return true;
    }

    function updateBlockHeader(
        bytes memory _blockHeadersBytes
    ) external override whenNotPaused {
        Verify.BlockHeader[] memory _blockHeaders = abi.decode(
            _blockHeadersBytes,
            (Verify.BlockHeader[])
        );

        require(confirms > 0, " not initialize");

        require(_blockHeaders.length == confirms, "not enough");

        _lastSyncedBlock += Verify.getEpochNumber(chainId,_lastSyncedBlock + 1);

        require(
            _blockHeaders[0].number == _lastSyncedBlock,
            "invalid syncing block"
        );
        // index 0 header verify by pre validators others by index 0 getValidators
        validators[(_lastSyncedBlock + 1) / Verify.getEpochNumber(chainId,_lastSyncedBlock + 1)] = Verify.getValidators(
            _blockHeaders[0].extraData
        );
        require(_verifyBlockHeaders(_blockHeaders), "blocks verify fail");

        emit UpdateBlockHeader(tx.origin, _blockHeaders[0].number);
    }

    function verifyProofData(
        bytes memory _receiptProof
    )
        external
        view
        override
        returns (bool success, string memory message, bytes memory logs)
    {
        ProofData memory proof = abi.decode(_receiptProof, (ProofData));

        Verify.BlockHeader[] memory headers = proof.headers;

        require(confirms > 0, " not initialize");

        require(headers.length == confirms, "not enough");

        require(
            headers[0].number >= minValidBlocknum &&
                headers[headers.length - 1].number <= maxCanVerifyNum(),
            "Can not verify blocks"
        );

        success = _verifyBlockHeaders(headers);
        if (!success) {
            message = "invalid proof blocks";
        } else {
            bytes32 rootHash = bytes32(headers[0].receiptsRoot);
            (success, logs) = Verify.validateProof(
                rootHash,
                proof.receiptProof,
                mptVerify
            );

            if (!success) {
                message = "mpt verify fail";
            }
        }
    }

    function _initBlock(Verify.BlockHeader memory _header) internal {
        require(_lastSyncedBlock == 0, "already init");
        require((_header.number + 1) % Verify.getEpochNumber(chainId,_header.number + 1) == 0, "invalid init block");

        bytes memory validator = Verify.getValidators(_header.extraData);
        require(validator.length >= ADDRESS_LENGTH, "no validator init");

        validators[(_header.number + 1) / Verify.getEpochNumber(chainId,_header.number + 1)] = validator;

        _lastSyncedBlock = _header.number;

        minValidBlocknum = _header.number + 1;
    }

    function _verifyBlockHeaders(
        Verify.BlockHeader[] memory _blockHeaders
    ) internal view returns (bool) {
        for (uint256 i = 0; i < _blockHeaders.length; i++) {
            if (i == 0) {
                require(
                    Verify.validateHeader(
                        _blockHeaders[i],
                        minEpochBlockExtraDataLen,
                        _blockHeaders[i],
                        chainId
                    ),
                    "invalid bock header"
                );
            } else {
                require(
                    Verify.validateHeader(
                        _blockHeaders[i],
                        minEpochBlockExtraDataLen,
                        _blockHeaders[i - 1],
                        chainId
                    ),
                    "invalid bock header"
                );
            }

            address signer = Verify.recoverSigner(_blockHeaders[i]);
            require(
                Verify.containValidator(
                    validators[_blockHeaders[i].number / Verify.getEpochNumber(chainId,_blockHeaders[i].number)],
                    signer
                ),
                "invalid block header singer"
            );
        }

        return true;
    }

    function _removeExcessEpochValidators() internal {

        if(_lastSyncedBlock < EPOCH_NUM * MAX_SAVED_EPOCH_NUM) {
            return;
        }
        uint256 remove = _lastSyncedBlock - EPOCH_NUM * MAX_SAVED_EPOCH_NUM;

        if (
            remove + Verify.getEpochNumber(chainId,remove) > minValidBlocknum &&
            validators[(remove + 1) / Verify.getEpochNumber(chainId,remove)].length > 0
        ) {
            minValidBlocknum = remove + Verify.getEpochNumber(chainId,remove) + 1;
            delete validators[(remove + 1) / Verify.getEpochNumber(chainId,remove)];
        }
    }

    function getBytes(
        ProofData memory _proof
    ) public pure returns (bytes memory) {
        return abi.encode(_proof);
    }

    function getHeadersBytes(
        Verify.BlockHeader[] memory _blockHeaders
    ) public pure returns (bytes memory) {
        return abi.encode(_blockHeaders);
    }

    function headerHeight() external view override returns (uint256) {
        return _lastSyncedBlock;
    }

    function maxCanVerifyNum() public view returns (uint256) {
        return _lastSyncedBlock + Verify.getEpochNumber(chainId,_lastSyncedBlock + 1);
    }

    function verifiableHeaderRange()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (minValidBlocknum, maxCanVerifyNum());
    }

    /** UUPS *********************************************************/
    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == _getAdmin(), "LightNode: only Admin can upgrade");
    }

   function changeAdmin() public {
        require(_pendingAdmin == msg.sender, "only pendingAdmin");
        emit AdminTransferred(_getAdmin(),_pendingAdmin);
        _changeAdmin(_pendingAdmin);
    }


    function pendingAdmin() external view returns(address){
        return _pendingAdmin;
    }

    function setPendingAdmin(address pendingAdmin_) public onlyOwner {
        require(pendingAdmin_ != address(0), "Ownable: pendingAdmin is the zero address");
        emit ChangePendingAdmin(_pendingAdmin, pendingAdmin_);
        _pendingAdmin = pendingAdmin_;
    }

    function getAdmin() external view returns (address) {
        return _getAdmin();
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}
