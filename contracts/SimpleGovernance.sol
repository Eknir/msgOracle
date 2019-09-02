pragma solidity ^0.5.10;
import "./../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./../node_modules/openzeppelin-solidity/contracts/access/Roles.sol";

/**
@title SimpleGovernance
@author Rinke Hendriksen <rinke@ethswarm.org>
@notice defines a simple governance scheme where governers can create proposals and update the governance scheme.
Additional roles can be made to facilitate granular access control by contracts inheriting this contract.
 */
contract SimpleGovernance {

    using SafeMath for uint256;
    using Roles for Roles.Role;

    event GovernerAdded(address indexed account);
    event GovernerRemoved(address indexed account);
    event LogNewProposal(bytes32 indexed proposal);
    event LogProposalDeclined(bytes32 indexed proposal);
    event LogVote(address indexed voter, bytes32 indexed proposal);
    event LogSetGovernersPercentageNeeded(uint256 governersPercentageNeeded);

    Roles.Role private _governers;

    uint256 public governersCount;
    uint256 public governersPercentageNeeded;

    struct Proposal {
        uint256 endsAt;
        uint256 voteCount;
        mapping(address => bool) gavePermission;
    }

    mapping(bytes32 => Proposal) public proposalRegistry;

    modifier onlyGoverner {
        require(_governers.has(msg.sender), "SimpleGovernance: caller does not have the governer role");
        _;
    }

    /**
    @notice sets the initial governers, governersPercentageNeeded and votingWindow.
    @param initialGoverner the initial governer who can vote and start new proposals
    @param _governersPercentageNeeded specifies the percentage of total governers needed to vote in favor for a certain proposal to become effective
    */
    constructor(address initialGoverner, uint256 _governersPercentageNeeded) public {
        _setGovernersPercentageNeeded(_governersPercentageNeeded);
        _addGoverner(initialGoverner);
    }

   /**
    @notice tells whether a certain proposal is valid
    @param proposal the unique ID of a proposal.
    A proposal's ID is defined by: keccak256(abi.encodePacked("TYPE", arg, proposalNonce)), where:
    -"TYPE" signals what the proposal is about,
    -arg what is proposed and
    -nonce just a number to ensure uniqueness
    @return whether the proposal is valid
    */
    function isValidProposal(bytes32 proposal) public view returns(bool) {
        if(
            proposalRegistry[proposal].voteCount.mul(100) >= governersCount.mul(governersPercentageNeeded)
        ) {
            return true;
        } else {
            return false;
        }
    }

    /**
    @notice creates a new proposal with an endTime
    @dev check the Natspec for functions which require a valid proposal on how to construct the parameter proposal
    @param proposal the unique ID of a proposal.
    @param endsAt when the proposal ends. It is envisioned that for every type of proposals, there is a guideline on how long it may run.
    If endsAt is not in accordance with this, it might be rejected
    A proposal's ID is defined by: keccak256(abi.encodePacked("TYPE", arg, proposalNonce)), where:
    -"TYPE" signals what the proposal is about,
    -arg what is proposed and
    -nonce just a number to ensure uniqueness
    */
    function newProposal(bytes32 proposal, uint256 endsAt) public onlyGoverner {
        require(proposalRegistry[proposal].endsAt == 0, "SimpleGovernance: proposal existing");
        require(endsAt >= now, "SimpleGovernance: endsAt must be in the future");
        proposalRegistry[proposal] = Proposal(endsAt, 0);
        emit LogNewProposal(proposal);
    }

    /**
    @notice declines an existing proposal
    @dev a governer can start a proposal by itself, and put an endTime very far in the future. To take away uncertainty about such pending proposals,
    we must have the possibility to annul a proposal.
    A proposal can be made and voted upon via the functions newProposal and vote (respectively).
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("DP", proposal, proposalNonce))
    This functions prevents new votes to be cast in favor of the proposal. It does NOT prevent an proposal with enough votes to be implemented
    @param proposal the unique ID of the proposal we want to cancel.
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
    If endsAt is not in accordance with this, it might be rejected
    A proposal's ID is defined by: keccak256(abi.encodePacked("TYPE", arg, proposalNonce)), where:
    -"TYPE" signals what the proposal is about,
    -arg what is proposed and
    -nonce just a number to ensure uniqueness
    */
    function declineProposal(bytes32 proposal, bytes32 proposalNonce) public {
        require(isValidProposal(keccak256(abi.encodePacked("DP", proposal, proposalNonce))), "SimpleGovernance: no valid proposal");
        // endsAt set to one, meaning it cannot be voted upon anymore. If there are already enoug
        proposalRegistry[proposal].endsAt = 1;
        emit LogProposalDeclined(proposal);
    }

    /**
    @notice vote on a pending proposal
    @dev governers can vote on a proposal to make this proposal valid (see: isValidProposal) and implement a change
    check the Natspec for functions which require a valid proposal on how to construct the parameter proposal
    @param proposal the unique ID of a proposal.
    A proposal's ID is defined by: keccak256(abi.encodePacked("TYPE", arg, proposalNonce)), where:
    -"TYPE" signals what the proposal is about,
    -arg what is proposed and
    -nonce just a number to ensure uniqueness
    */
    function vote(bytes32 proposal) public onlyGoverner {
        require(!proposalRegistry[proposal].gavePermission[msg.sender], "SimpleGovernance: already voted");
        require(proposalRegistry[proposal].endsAt != 0, "SimpleGovernance: proposal not started");
        require(proposalRegistry[proposal].endsAt <= now, "SimpleGovernance: proposal ended");
        proposalRegistry[proposal].gavePermission[msg.sender] == true;
        proposalRegistry[proposal].voteCount++;
        emit LogVote(msg.sender, proposal);
    }

    /**
    @notice add a new governer when a valid proposal is present
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively).
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("AG", newGoverner, proposalNonce))
    @param newGoverner can vote and start new proposal
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
    */
    function addGoverner(address newGoverner, bytes32 proposalNonce) public {
        require(isValidProposal(keccak256(abi.encodePacked("AG", newGoverner, proposalNonce))), "SimpleGovernance: no valid proposal");
        _addGoverner(newGoverner);
    }

    /**
    @notice remove a governer when a valid proposal is present
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively).
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("RK", governer, proposalNonce))
    @param governer to be removed governer can vote and start new proposal
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
    */
    function removeGoverner(address governer, bytes32 proposalNonce) public {
        require(isValidProposal(keccak256(abi.encodePacked("RK", governer, proposalNonce))), "SimpleGovernance: no valid proposal");
        _addGoverner(governer);
    }

    /**
    @notice sets the percentage of governers needed to vote in favour for a proposal to become valid (see: isValidProposal) when a valid proposal is present
    @dev A proposal can be made and voted upon via the functions newProposal and vote (respectively).
    @param _governersPercentageNeeded specifies the percentage of total governers needed to vote in favor for a certain proposal to become effective
    The bytes32 proposal value (functions: newProposal and vote) is keccak256(abi.encodePacked("SGPN", _governersPercentageNeeded, proposalNonce))
    @param proposalNonce Value needed to ensure always-unique proposal identifiers.
    */
    function changeGovernersPercentageNeeded(uint256 _governersPercentageNeeded, bytes32 proposalNonce) public {
        require(isValidProposal(keccak256(abi.encodePacked(
            "CGPN",
            _governersPercentageNeeded,
            proposalNonce))),
            "SimpleGovernance: no valid proposal"
        );
        _setGovernersPercentageNeeded(_governersPercentageNeeded);
    }

    /**
    @notice Internal function which adds a governer and emits a GovernerAdded event.
    @dev Called in this contract by functions: constructor and addGoverner.
     */
    function _addGoverner(address account) internal {
        _governers.add(account);
        governersCount++;
        emit GovernerAdded(account);
    }

    /**
    @notice Internal function which removes a governer and emits a GoverRemoved event.
    @dev Called in this contract by removeGoverner.
     */
    function _removeGoverner(address account) internal {
        _governers.remove(account);
        governersCount--;
        emit GovernerRemoved(account);
    }

    /**
    @notice Internal function which sets the governerPercentageNeeded after verifying that this value is below 100
    @dev Called in this contract by functions: constructor and changeGovernersPercentageNeeded.
     */
    function _setGovernersPercentageNeeded(uint256 _governersPercentageNeeded) internal {
        require(_governersPercentageNeeded <= 100, "SimpleGovernance: _governersPercentageNeeded not below 100");
        governersPercentageNeeded = _governersPercentageNeeded;
        emit LogSetGovernersPercentageNeeded(_governersPercentageNeeded);
    }
}