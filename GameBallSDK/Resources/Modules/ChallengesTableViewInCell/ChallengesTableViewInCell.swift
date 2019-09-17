//
//  ChallengesTableViewInCell.swift
//  GameBallSDK
//
//  Created by Martin Sorsok on 7/27/19.
//

import UIKit

class ChallengesTableViewInCell: UITableViewCell,UITableViewDelegate,UITableViewDataSource {
    
    
    var referalHeaderViewTableView = "ReferalHeaderViewTableView"
    var referalFriendTableViewCell = "ReferalFriendTableViewCell"
    
    var leaderBoardTableViewCell = "LeaderBoardTableViewCell"
    var leaderBoardHeaderView = "LeaderBoardHeaderView"
    
    
    var notificationsTableViewCell = "NotificationsTableViewCell"
    var notificationHeaderView = "NotificationHeaderView"
    
    
    
     var filteredString = ""
    var sharingCodeText = ""
    var challenges: [Challenge] = []
    var leaderboardProfiles: [Profile] = []
    var notifications: [NotificationGB] = []
    var playerRank: LeaderboardPlayerRank?
    weak var delegate:TabBarDelegate?
    private let challengesViewModel = ChallengesViewModel()
    var  currentFeature = 1
    
    @IBOutlet weak var tableView: UITableView!{
        didSet{
            tableView.separatorStyle = .none
            tableView.dataSource = self
            tableView.delegate = self
            tableView.isHidden = true

            tableView.showsVerticalScrollIndicator = false
            tableView.register(UINib(nibName: referalFriendTableViewCell, bundle: nil), forCellReuseIdentifier: referalFriendTableViewCell)
            tableView.register(UINib(nibName: referalHeaderViewTableView, bundle: nil), forHeaderFooterViewReuseIdentifier: referalHeaderViewTableView)
            tableView.register(UINib(nibName: referalHeaderViewTableView, bundle: nil), forHeaderFooterViewReuseIdentifier: referalHeaderViewTableView)
            
            tableView.register(UINib(nibName: leaderBoardTableViewCell, bundle: nil), forCellReuseIdentifier: leaderBoardTableViewCell)
            tableView.register(UINib(nibName: leaderBoardHeaderView, bundle: nil), forHeaderFooterViewReuseIdentifier: leaderBoardHeaderView)
            
            tableView.register(UINib(nibName: notificationsTableViewCell, bundle: nil), forCellReuseIdentifier: notificationsTableViewCell)
            tableView.register(UINib(nibName: notificationHeaderView, bundle: nil), forHeaderFooterViewReuseIdentifier: notificationHeaderView)
        }
    }
    @IBOutlet weak var tableViewHeightConstraint: NSLayoutConstraint!
    
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        nc.addObserver(self, selector: #selector(tabBarTapped), name: Notification.Name("tabBarTapped"), object: nil)


    }
    

 
    
   
    @objc func tabBarTapped(_ notification:Notification) {
       // self.delegate?.dataReady(tableview: self.tableView)

        guard let featureNumber = notification.object as? Int else {
            return
        }
        delegate?.dataReady(tableview: self.tableView)
//        switch featureNumber {
//        case Features.LeaderBoard.rawValue:
//            fetchLeaderBoardDate()
//        case Features.Notifications.rawValue:
//            fetchNotificationsData()
//        default:
//            fetchData()
//        }
     //   print(featureNumber)
        
    }

    



    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Configure the view for the selected state
    }
    
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if currentFeature == Features.LeaderBoard.rawValue {
            return self.leaderboardProfiles.count
        } else if currentFeature == Features.Notifications.rawValue {
            return self.notifications.count

        } else {
            return self.challenges.count
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if currentFeature == Features.LeaderBoard.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier:leaderBoardTableViewCell ) as! LeaderBoardTableViewCell
            cell.selectionStyle = .none
            
            if leaderboardProfiles.count  > 0 {
                cell.rankNumber = (indexPath.row + 1)
                cell.profile = leaderboardProfiles[indexPath.row]
            }
            return cell
        }     else    if currentFeature == Features.Notifications.rawValue {
            let cell = tableView.dequeueReusableCell(withIdentifier:notificationsTableViewCell ) as! NotificationsTableViewCell
            cell.selectionStyle = .none
            
            if notifications.count  > 0 {
                cell.notification = notifications[indexPath.row]
            }
            return cell
        } else  if currentFeature == Features.FriendReferal.rawValue{
            let cell = tableView.dequeueReusableCell(withIdentifier: referalFriendTableViewCell) as! ReferalFriendTableViewCell
            cell.selectionStyle = .none
            cell.challenge = challenges[indexPath.row]
            return cell
        }
        
        return UITableViewCell()
    }
 
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        if currentFeature == Features.LeaderBoard.rawValue {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: leaderBoardHeaderView) as! LeaderBoardHeaderView
            headerView.filterByLabel.text = filteredString
            headerView.yourRankValue.text = "\(playerRank?.rowOrder ?? 0)/\(playerRank?.playersCount ?? 0)"
            headerView.filterBtn.addTarget(self, action: #selector(tappedLeaderBoardFilter), for: .touchUpInside)
            return  headerView
        } else  if currentFeature == Features.Notifications.rawValue {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: notificationHeaderView) as! NotificationHeaderView
            
            return  headerView
        } else {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: referalHeaderViewTableView) as! ReferalHeaderViewTableView
            headerView.copyBtn.addTarget(self, action: #selector(copyAction), for: .touchUpInside)
            self.sharingCodeText = headerView.textField.text ?? ""
            return  headerView
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if currentFeature == Features.LeaderBoard.rawValue {
            return 94
            
        } else if currentFeature == Features.Notifications.rawValue {
            return 58
            
        } else {
            return 172
            
        }
    }
    
    @objc func copyAction(sender: UIButton!) {
        
        print(sharingCodeText)
        
        self.delegate?.shareText(text: sharingCodeText)
    }
    
    @objc func tappedLeaderBoardFilter(sender: UIButton!) {
        
        print(sharingCodeText)
        
        self.delegate?.tappedLeaderBoardFilter()
    }
    
}
