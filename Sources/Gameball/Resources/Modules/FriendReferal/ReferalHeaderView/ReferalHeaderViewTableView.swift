//
//  ReferalHeaderViewCollectionReusableView.swift
//  GameBallSDK
//
//  Created by Martin Sorsok on 7/26/19.
//

import UIKit

class ReferalHeaderViewTableView: UITableViewHeaderFooterView {
    let userCache = UserProfileCache.get()

    @IBOutlet weak var titleLabel: UILabel!{
        didSet {
            titleLabel.text =  Gameball.clientBotStyle?.referralHeadLine
            
            if GB_Localizator.sharedInstance.language == Languages.arabic {
                titleLabel.font = Fonts.cairoBoldFont16
                
            } else {
                titleLabel.font = Fonts.montserratSemiBoldFont16
            }
            titleLabel.textColor = Colors.appMainColor ?? .black
        }
    }
    @IBOutlet weak var describtionLabel: UILabel!{
        didSet {
            describtionLabel.text =  Gameball.clientBotStyle?.referralText
            
            if GB_Localizator.sharedInstance.language == Languages.arabic {
                describtionLabel.font = Fonts.cairoRegularFont12
                
            } else {
                describtionLabel.font = Fonts.montserratLightFont12
            }
      
        }
    }
    @IBOutlet weak var referalIcon: UIImageView! {
        didSet {
            setImage(withURL: Gameball.clientBotStyle?.referralIcon ?? "")
            
        }
    }
    @IBOutlet weak var textField: UITextField!{
        didSet{
            
            textField.text = userCache?.dynamicLink
            if GB_Localizator.sharedInstance.language == Languages.arabic {
                textField.font = Fonts.cairoRegularFont10
                
            } else {
                textField.font = Fonts.montserratLightFont10
            }
        

            textField.textColor = Colors.appGray128
           textField.layer.cornerRadius = 15
            textField.clipsToBounds = true
            textField.backgroundColor = Colors.appGray242
            textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 11, height: textField.frame.height))
            textField.leftViewMode = .always
            if #available(iOS 11.0, *) {
                if GB_Localizator.sharedInstance.language == Languages.arabic {
                    textField.layer.maskedCorners = [ .layerMaxXMaxYCorner,.layerMaxXMinYCorner]

                } else {
                    textField.layer.maskedCorners = [ .layerMinXMinYCorner,.layerMinXMaxYCorner]
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    @IBOutlet weak var copyBtn: UIButton!{
        didSet{
            if #available(iOS 11.0, *) {
                if GB_Localizator.sharedInstance.language == Languages.arabic {
                    copyBtn.layer.maskedCorners = [ .layerMinXMinYCorner,.layerMinXMaxYCorner]

                } else {
                    copyBtn.layer.maskedCorners = [ .layerMaxXMaxYCorner,.layerMaxXMinYCorner]

                }
            } else {
                // Fallback on earlier versions
            }
            
            copyBtn.setTitle(GB_LocalizationsKeys.FriendReferalScreen.copy.rawValue.localized, for: .normal)
            if GB_Localizator.sharedInstance.language == Languages.arabic {
                copyBtn.titleLabel?.font = Fonts.cairoBoldFont12
                
            } else {
                copyBtn.titleLabel?.font = Fonts.montserratSemiBoldFont12
            }
            copyBtn.setTitleColor(.white, for: .normal)
            copyBtn.layer.cornerRadius = 15
            copyBtn.clipsToBounds = true
            copyBtn.backgroundColor = Colors.appMainColor ?? .black
        }
    }
    
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }
    
    @IBAction func copyBtnAction(_ sender: Any) {
        
        
    }
    func setImage(withURL: String) {
         let path = withURL
         NetworkManager.shared().loadImage(path: path.replacingOccurrences(of: " ", with: "%20")) { (myImage, error) in
             if let errorModel = error {
                  Helpers().dPrint(errorModel.description)
             }
             else {
             }
             if let result = myImage {
                 DispatchQueue.main.async {
                     self.referalIcon.image = result
                     self.referalIcon.alpha = 0
                     UIView.animate(withDuration: 1.0, animations: {
                         self.referalIcon.alpha = 1.0
                     })
                 }
             }
         }
     }

}
