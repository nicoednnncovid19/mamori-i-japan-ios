//
//  HomeViewController.swift
//  TraceCovid19
//
//  Created by yosawa on 2020/04/01.
//

import UIKit
import KeychainAccess
import NVActivityIndicatorView
import SnapKit

enum UserStatus {
    case usual
    case semiUsual
    case attension
    case positive

    static let usualUpperLimitCount = 25
}

final class HomeViewController: UIViewController, NavigationBarHiddenApplicapable, NVActivityIndicatorViewable {
    @IBOutlet weak var headerImageView: UIImageView!
    @IBOutlet weak var headerBaseView: UIView!
    @IBOutlet weak var topMarginConstraint: NSLayoutConstraint!
    @IBOutlet weak var dateLabel: UILabel!

    var keychain: KeychainService!
    var ble: BLEService!
    var deepContactCheck: DeepContactCheckService!
    var positiveContact: PositiveContactService!
    var tempId: TempIdService!

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()

        if fetchTempIDIfNotHave() == false {
            // 持っているならばBLEをオンにする
            ble.turnOn()
        }

        // バックグラウンドから復帰時に陽性者取得を行う
        NotificationCenter.default.addObserver(self, selector: #selector(getPositiveContacts), name: UIApplication.willEnterForegroundNotification, object: nil)

        #if DEBUG
        let debugItem = UIBarButtonItem(title: "デバッグ", style: .plain, target: self, action: #selector(gotoDebug))
        navigationItem.leftBarButtonItem = debugItem
        #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        getPositiveContacts()
        reloadViews()
    }

    @IBAction func tappedMenuButton(_ sender: Any) {
        gotoMenu()
    }

    @IBAction func tappedShareButton(_ sender: Any) {
        shareApp()
    }

    @IBAction func tappedUploadButton(_ sender: Any) {
        gotoUpload()
    }

    @discardableResult
    private func fetchTempIDIfNotHave() -> Bool {
        guard !tempId.hasTempIDs else { return false }
        // TODO: 多重カウントによるアニメーション管理
        startAnimating(type: .circleStrokeSpin)

        tempId.fetchTempIDs { [weak self] result in
            self?.stopAnimating()

            switch result {
            case .failure:
                // TODO: エラーの見せ方
                self?.showAlert(message: "読み込みに失敗しました", buttonTitle: "再読み込み") { [weak self] _ in
                    self?.fetchTempIDIfNotHave()
                }
            case .success:
                // 成功ならBLEを開始する
                self?.ble.turnOn()
            }
        }
        return true
    }

    private func setupViews() {
        // SafeAreaを考慮したマージン設定
        topMarginConstraint.constant = topBarHeight

        // ドロップシャドー
        headerBaseView.layer.shadowOffset = CGSize(width: 0.0, height: 4.0)
        headerBaseView.layer.shadowRadius = 10.0
        headerBaseView.layer.shadowColor = UIColor(hex: 0x1d2a3e, alpha: 0.1).cgColor
        headerBaseView.layer.shadowOpacity = 1.0

        // 角丸
        headerBaseView.layer.cornerRadius = 8.0
        headerBaseView.clipsToBounds = false
    }

    private func reloadViews() {
        // TODO: 時間
        dateLabel.text = "最終更新: \(Date().toString(format: "MM月dd日HH時"))"
        redrawHeaderView()
    }

    private func redrawHeaderView() {
        // ヘッダのSubviewを再描画
        headerBaseView.subviews.forEach { $0.removeFromSuperview() }
        switch status {
        case .usual:
            headerImageView.image = Asset.homeUsualHeader.image
            let header = HomeUsualHeaderView(frame: headerBaseView.frame)
            header.set(contactCount: 10) // TODO: カウントセット
            headerBaseView.addSubview(header)
            header.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        case .semiUsual:
            headerImageView.image = Asset.homeSemiUsualHeader.image
            let header = HomeUsualHeaderView(frame: headerBaseView.frame)
            header.set(contactCount: 1000) // TODO: カウントセット
            headerBaseView.addSubview(header)
            header.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        case .attension:
            headerImageView.image = Asset.homeAttensionHeader.image
            let header = HomeAttensionHeaderView(frame: headerBaseView.frame)
            // header.set(contactCount: 1000) // TODO: 接触情報セット
            headerBaseView.addSubview(header)
            header.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        case .positive:
            headerImageView.image = Asset.homePositiveHeader.image
            let header = HomePositiveHeaderView(frame: headerBaseView.frame)
            headerBaseView.addSubview(header)
            header.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
    }

    func gotoMenu() {
        navigationController?.pushViewController(MenuViewController.instantiate(), animated: true)
    }

    func shareApp() {
        let shareText = "シェア文言"
        let shareURL = NSURL(string: "https://corona.go.jp/")!
        let shareImage = UIImage(named: "Group")!

        let activityViewController = UIActivityViewController(activityItems: [shareText, shareURL, shareImage], applicationActivities: nil)

        // 使用しないタイプ
        let excludedActivityTypes: [UIActivity.ActivityType] = [
            .saveToCameraRoll,
            .print,
            .openInIBooks,
            .assignToContact,
            .addToReadingList,
            .copyToPasteboard,
            .init(rawValue: "com.apple.reminders.RemindersEditorExtension"), // リマインダー
            .init(rawValue: "com.apple.mobilenotes.SharingExtension") // メモ
        ]

        activityViewController.excludedActivityTypes = excludedActivityTypes

        // UIActivityViewControllerを表示
        present(activityViewController, animated: true, completion: nil)
    }

    func gotoUpload() {
        let navigationController = CustomNavigationController(rootViewController: TraceDataUploadViewController.instantiate())
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true, completion: nil)
    }

    #if DEBUG
    @objc
    func gotoDebug() {
        let navigationController = CustomNavigationController(rootViewController: DebugViewController.instantiate())
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true, completion: nil)
    }
    #endif
}

extension HomeViewController {
    private var status: UserStatus {
        // TODO: DEBUG
        return .positive

        if positiveContact.isPositiveMyself() {
            return .positive
        }
        if let latestPerson = positiveContact.getLatestContactedPositivePeople() {
            return .attension //.contactedPositive(latest: latestPerson)
        }
        // TODO: カウント
        return .usual
    }

    @objc
    func getPositiveContacts() {
        startAnimating(type: .circleStrokeSpin)

        // TODO: モーダル先からログアウトをする場合、ここの処理が呼ばれてしまうので余裕があればカバーする
        positiveContact.load { [weak self] result in
            self?.stopAnimating()

            switch result {
            case .success:
                self?.execDeepContactCheck()
            case .failure(.noNeedToLoad):
                break
            case .failure(.error(let error)):
                // TODO: エラー表示
                print("[Home] error: \(String(describing: error))")
            }
        }
    }

    private func execDeepContactCheck() {
        startAnimating(type: .circleStrokeSpin)
        deepContactCheck.checkStart { [weak self] in
            self?.stopAnimating()
            print("[Home] deep contact check finished: \($0)")
            self?.reloadViews()
        }
    }
}

 // TODO: あとできりだす
extension UIViewController {
    var topBarHeight: CGFloat {
        return UIApplication.shared.statusBarFrame.height +
            (navigationController?.navigationBar.bounds.height ?? 0.0)
    }
}
