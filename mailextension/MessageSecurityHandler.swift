//
//  MessageSecurityHandler.swift
//  mailextension
//
//  Created by Tyler Cross on 8/6/25.
//

import MailKit

class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {

    static let shared = MessageSecurityHandler()

    // MARK: - Encoding Messages

    func getEncodingStatus(for message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void) {
        // Indicate whether you support signing, encrypting, or both. If the
        // message contains recipients that you can't sign or encrypt for,
        // specify an error and include the addresses in the
        // addressesFailingEncryption array parameter. Update this code with
        // the options your extension supports.
        let status = MEOutgoingMessageEncodingStatus(canSign:false, canEncrypt:false, securityError:nil, addressesFailingEncryption:[])

        // Call the completion handler with the message status.
        completionHandler(status)
    }

    func encode(_ message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEMessageEncodingResult) -> Void) {
        // The result of the encoding operation. This object contains
        // the encoded message or an error to indicate what failed.
        let result: MEMessageEncodingResult
        
        // Add code here to sign and/or encrypt the message.
        //
        // If the encoding is successful, you create an instance
        // of MEEncodedOutgoingMessage that contains the encoded data and
        // indications whether the data is signed and/or encrypted.
        // For example:
        //
        // encodedMessage = MEEncodedOutgoingMessage(rawData:encodedData, isSigned:true, isEncrypted:true)
        //
        // Finally, create an MEMessageEncodingResult that includes the
        // MEEncodedOutgoingMessage or errors to indicate why the encoding
        // failed. If the message doesn't need to be encoded, pass nil,
        // otherwise pass an MEEncodedOutgoingMessage as shown above.
        result = MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
      
        // Call the completion handler with the result, or nil if
        // the extension didn't attempt to encode the message at all.
        completionHandler(result);
    }

    // MARK: - Decoding Messages

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        // In this method, you decode the message data. Create an
        // MEMessageSecurityInformation object to capture details about the decoded
        // message. If an error occurs, create an NSError that describes the
        // failure, and specify it in the security information object. For example:
        //
        // let securityInfo = MEMessageSecurityInformation(signers: [], isEncrypted: false, signingError: nil, encryptionError: nil)
        //
        // Create a decoded message object that contains the decoded data and the
        // security information. For example:
        //
        // let decodedData = ... 
        // let decodedMessage = MEDecodedMessage(data: decodedData, securityInformation: securityInfo, context: nil)
        
        // If the message doesn't need to be decoded, return nil.
        // Otherwise return an MEDecodedMessage, as shown above. 
        return nil;
    }
 
    // MARK: - Displaying Security Information

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? {
        // Return a view controller that shows details about the encoded message.
        return MessageSecurityViewController(nibName: "MessageSecurityViewController", bundle: Bundle.main
        )
    }

    // MARK: mark - Displaying Additional Context

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? {
        // Return a view controller that can show additional message context.
        return nil
    }

    func primaryActionClicked(forMessageContext context: Data, completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        // Provide a view controller that is displayed when user clicks on the message banner that is displayed when viewing a decoded mail message.
        completionHandler(nil)
    }
}
