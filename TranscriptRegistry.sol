// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ContractRegistry} from "@flarenetwork/flare-periphery-contracts/coston2/ContractRegistry.sol";
import {IJsonApi}       from "@flarenetwork/flare-periphery-contracts/coston2/IJsonApi.sol";
import {IFdcHub}        from "@flarenetwork/flare-periphery-contracts/coston2/IFdcHub.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Transcript Registry
 * @dev Requests and stores verified student transcript data via FDC
 */
contract TranscriptRegistry is Ownable {
    struct Transcript {
        string studentId;
        string university;
        string degree;
        string graduationDate;
        string transcriptHash;
    }

    /// @notice on-chain record of verified transcripts by studentId
    mapping(string => Transcript) public records;

    /// @notice Emitted when a raw FDC attestation request is sent
    event AttestationRequested(bytes data, uint256 fee);

    /// @notice Emitted when a transcript is successfully added
    event TranscriptAdded(string indexed studentId);

    /**
     * @notice Send a raw JSON-API attestation request to FDC
     * @param requestData The ABI-encoded payload for the JSON-API request
     * @dev Build requestData off-chain by encoding your URL, JQ, and ABI signature
     */
    function requestTranscript(bytes calldata requestData)
        external
        payable
        onlyOwner
    {
        IFdcHub hub = ContractRegistry.getFdcHub();
        hub.requestAttestation{value: msg.value}(requestData);
        emit AttestationRequested(requestData, msg.value);
    }

    /**
     * @notice Add a verified transcript from an FDC JSON-API proof
     * @param proof The IJsonApi.Proof obtained from the DA layer
     */
    function addTranscript(
        IJsonApi.Proof calldata proof
    ) external onlyOwner {
        require(
            ContractRegistry
                .auxiliaryGetIJsonApiVerification()
                .verifyJsonApi(proof),
            "Invalid FDC proof"
        );

        Transcript memory t = abi.decode(
            proof.data.responseBody.abi_encoded_data,
            (Transcript)
        );

        records[t.studentId] = t;
        emit TranscriptAdded(t.studentId);
    }
}
