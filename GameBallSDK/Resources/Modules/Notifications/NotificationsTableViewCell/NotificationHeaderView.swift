//
//  NotificationHeaderView.swift
//  GameBallSDK
//
//  Created by Martin Sorsok on 8/15/19.
//

import UIKit

class NotificationHeaderView: UITableViewHeaderFooterView {
    
    
    
    @IBOutlet weak var titleLabel: UILabel!{
        didSet {
            titleLabel.text =  LocalizationsKeys.NotificationsScreen.notifications.rawValue.localized
            
            if Localizator.sharedInstance.language == Languages.arabic {
                titleLabel.font = Fonts.cairoBoldFont16
                
            } else {
                titleLabel.font = Fonts.montserratSemiBoldFont16
            }
            titleLabel.textColor = Colors.appMainColor ?? .black
        }
}

}
