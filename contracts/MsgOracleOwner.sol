pragma solidity ^0.5.10;

import "./MsgOracle.sol";
import "./SimpleGovernance.sol";

import "./../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./../node_modules/openzeppelin-solidity/contracts/access/Roles.sol";

/**
@title MsgOracleOwner
@author Rinke Hendriksen <rinke@ethswarm.org>
@notice Proxy with access control for calling functions in MsgOracle. Access controll is two-tiered:
- a leader can call all functions defined in MsgOracle, excluding functions in Ownable
- a validProposal is needed (per SimpleGovernance) to add and remove leaders and to change the owner of MsgOracle
@dev Meant to be the owner (as per openzeppelin-solidity/contracts/ownership/Ownable.sol") of MsgOracle.
This smart-contract can be replaced as owner by calling callTransferOwnership.
 */
contract MsgOracleOwner {

    using SafeMath for uint256;
    using Roles for Roles.Role;

    MsgOracle msgOracle;
    SimpleGovernance simpleGovernance;

    uint256 public maxTTLChangePercentage;

    event LeaderAdded(address indexed account);
    event LeaderRemoved(address indexed account);
    event LogSetMaxTTLPercentage(uint256 maxTTLPercentage);

    Roles.Role private _leaders;

    modifier onlyLeader {
        require(_leaders.has(msg.sender), "MsgOracleOwner: caller does not have the leader role");
        _;
    }

    /**
    @notice Delegates to the SimpleGovernance constructor,
    add a leader, set msgOracle to implement MsgOracle at address _msgOracle and sets the maxTTLChangePercentage.
    @dev Solidity does not check wether a MsgOracle lives at address _msgOracle. This must be validated by the person calling this constructor.
    @param _simpleGovernance The address at which the SimpleGovernance contract lives.
    @param _msgOracle The address at which a MsgOracle contract lives.
    @param leader The initial leader.
    @param _maxTTLChangePercentage intitial percentage by how much the leader can maximally change TTL at MsgOracle.
    */
    constructor(
        address _simpleGovernance,
        address _msgOracle,
        address leader,
        uint256 _maxTTLChangePercentage
    ) public {
        simpleGovernance = SimpleGovernance(_simpleGovernance);
        msgOracle = MsgOracle(_msgOracle);
        _addLeader(leader);
        _setMaxTTLChangePercentage(_maxTTLChangePercentage);
    }

    /**
    @notice Adds a leader when a valid proposal (per SimpleGovernance) is present
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance
    @param account The to be added leader
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
     */
    function addLeader(address account, bytes32 proposalNonce) public {
        require(simpleGovernance.isValidProposal(
            keccak256(abi.encodePacked("AL", account, proposalNonce))
            ), "MsgOracleOwner: no valid proposal"
        );
        _addLeader(account);
    }

    /**
    @notice Removes a leader when a valid proposal (per SimpleGovernance) is present.
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance.
    @param account The to be removed leader.
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
     */
    function removeLeader(address account, bytes32 proposalNonce) public {
    require(simpleGovernance.isValidProposal(
            keccak256(abi.encodePacked("AL", account, proposalNonce))
        ), "MsgOracleOwner: no valid proposal"
    );
        _removeLeader(account);
    }

    /**
    @notice Changes maxTTL when a valid proposal (per SimpleGovernance) is present.
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance.
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("CMTCP", newMaxTTLChangePercentage, proposalNonce))
    @param newMaxTTLChangePercentage The to be removed leader.
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
     */
    function changeMaxTTLChangePercentage(uint256 newMaxTTLChangePercentage, bytes32 proposalNonce) public {
        require(simpleGovernance.isValidProposal(keccak256(
            abi.encodePacked(
                "CMTCP",
                newMaxTTLChangePercentage,
                proposalNonce
            ))), "MsgOracleOwner: no valid proposal");
        _setMaxTTLChangePercentage(newMaxTTLChangePercentage);
    }

    /**
    @notice Calls NewTTL (on MsgOrafrom MsgOracle) and set a new TTL within bounds. Only a leader can do this.
    @dev Bounds are set by maxTTLChangePercentage. See documentation at MsgOracle.
    */
    function callNewTTLByLeader(uint256 newTTL) public onlyLeader {
        uint256 TTL = msgOracle.TTL();
        require(newTTL.mul(100) <= TTL.mul(maxTTLChangePercentage.add(100)) &&
            newTTL.mul(100) >= TTL.mul(uint256(100).sub(maxTTLChangePercentage)),
            "MsgOracleOwner: newTTL out of bounds"
        );
        _callNewTTL(newTTL);
    }

    /**
    @notice Calls NewTTL (on MsgOrafrom MsgOracle) when a valid proposal (per SipmleGovernance) is present
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance.
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("CNTWP", newTTL, proposalNonce))
    See documentation at MsgOracle.
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
    */
    function callNewTTLWithProposal(uint256 newTTL, bytes32 proposalNonce) public {
        require(simpleGovernance.isValidProposal(
            keccak256(abi.encodePacked("CNTWP", newTTL, proposalNonce))
            ), "MsgOracleOwner: no valid proposal"
        );
        _callNewTTL(newTTL);
    }

    /**
    @notice Calls setMsgPrice (from MsgOracle). Only a leader can do this.
    @dev See documentation at MsgOracle.
    */
    function callSetMsgPrice(bytes32 swarmMsg, uint256 price, uint256 validFrom) public onlyLeader {
        msgOracle.setMsgPrice(swarmMsg, price, validFrom);
    }

    /**
    @notice Calls revertMsgPrice (from MsgOracle) when a valid proposal (per SimpleGovernance) is present.
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance.
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("CTO", newOwner, proposalNonce))
    See documentation at MsgOracle.
    Function needed to be able to undo any damage which a roque or uncarefull leader can do.
    */
    function callRevertMsgPrice(bytes32 swarmMsg, uint256 price, uint256 validFrom, bytes32 argHash, bytes32 proposalNonce) public {
        require(keccak256(abi.encodePacked(swarmMsg, price, validFrom)) == argHash, "MsgOracleOwner: argHash does not match arguments");
        require(simpleGovernance.isValidProposal(
            keccak256(abi.encodePacked("CRMP", argHash, proposalNonce))
            ), "MsgOracleOwner: no valid proposal"
        );
        msgOracle.revertMsgPrice(swarmMsg, price, validFrom);
    }

    /**
    @notice Calls transferOwnership (from MsgOracle) when a valid proposal (per SimpleGovernance) is present.
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance.
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("CTO", newOwner, proposalNonce))
    See documentation at MsgOracle
    */
    function callTransferOwnership(address newOwner, bytes32 proposalNonce) public {
        require(simpleGovernance.isValidProposal(
            keccak256(abi.encodePacked("CTO", newOwner, proposalNonce))
            ), "MsgOracleOwner: no valid proposal"
        );
        msgOracle.transferOwnership(newOwner);
    }

    /**
    @notice Calls renounceOwnership (from MsgOracle) when a valid proposal (per SimpleGovernance) is present.
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively) from SimpleGovernance.
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("CRO", address(0), proposalNonce))
    See documentation at MsgOracle
    */
    function callRenounceOwnership(bytes32 proposalNonce) public {
        require(simpleGovernance.isValidProposal(
            keccak256(abi.encodePacked("CRO", address(0), proposalNonce))
            ), "MsgOracleOwner: no valid proposal"
        );
        msgOracle.renounceOwnership();
    }

    /**
    @notice Internal function which calls newTTL (from MsgOracle).
    @dev called in this contract by callNewTTLWithProposal and callNewTTLByLeader
    */
    function _callNewTTL(uint256 newTTL) internal {
        msgOracle.newTTL(newTTL);
    }

    /**
    @notice Internal function which adds a leader and emits a LeaderAdded event.
    @dev Called in this contract by functions: constructor and addLeader.
     */
    function _addLeader(address account) internal {
        _leaders.add(account);
        emit LeaderAdded(account);
    }

    /**
    @notice Internal function which removes a leader and emits a LeaderRemoved event.
    @dev Called in this contract by removeLeader.
     */
    function _removeLeader(address account) internal {
        _leaders.remove(account);
        emit LeaderRemoved(account);
    }

    /**
    @notice Internal function sets maxTTL after confirming it is not above 100.
    @dev Called in this contract by functions: the constructor and changeMaxTTLChangePercentage
     */
    function _setMaxTTLChangePercentage(uint256 _maxTTLChangePercentage) internal {
        require(_maxTTLChangePercentage <= 100, "MsgOracleOwner: maxTTLChangePercentage cannot be more than 100");
        maxTTLChangePercentage = _maxTTLChangePercentage;
        emit LogSetMaxTTLPercentage(_maxTTLChangePercentage);
    }

}