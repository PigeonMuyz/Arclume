//
//  ProfileWidget.swift
//  Procyon
//
//  Created by Italo Mandara on 03/03/2026.
//

import SwiftUI
import Kingfisher
import AppKit

struct ProfileWidget: View {
    var identity: SteamIdentity?
    @EnvironmentObject var appGlobals: AppGlobals
    @State private var isLoading: Bool = true
    @State private var profileData: UserInfo? = nil
    @State private var showProfile: Bool = false

    init(identity: SteamIdentity? = nil) {
        self.identity = identity
    }

    private var displayedIdentity: SteamIdentity? {
        identity ?? appGlobals.activeSteamIdentity
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            if isLoading {
                ProgressView().scaleEffect(0.5)
            } else if let p = profileData {
                Button {
                    showProfile = true
                } label: {
                    HStack {
                        KFImage(URL(string: p.avatar))
                            .placeholder {
                                ProgressView()
                            }
                            .resizable()
                            .scaledToFit()
                            .mask(Circle())
                            .padding(5)
                            .frame(width: 40)
                        Text(p.personaName).lineLimit(1)
                    }.frame(maxWidth: 150, alignment: .init(horizontal: .leading, vertical: .center))
                }
                .buttonStyle(.plain)
            } else {
                if let identity = displayedIdentity {
                    HStack {
                        if let avatar = localAvatar(for: identity) {
                            Image(nsImage: avatar)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                                .padding(4)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .padding(5)
                        }
                        Text(identity.displayName).lineLimit(1)
                    }
                    .frame(
                        maxWidth: 150,
                        alignment: .init(horizontal: .leading, vertical: .center)
                    )
                    .help(L10n.format("Steam ID: %@", identity.steamID))
                } else if let bottlePath = URL(string: appGlobals.selectedBottle) {
                    if let fallbackProfileData = getSteamUserDataFallback(usingPath: appGlobals.windowsSteamFolder ?? bottlePath.appendingPathComponent(DEFAULT_STEAM_WINE_CONFIG_PATH)) {
                        HStack {
                            KFImage(URL(string: fallbackProfileData.avatar))
                                .resizable()
                                .scaledToFit()
                                .mask(Circle())
                                .padding(5)
                                .frame(width: 40)
                            Text(fallbackProfileData.personaName).lineLimit(1)
                        }.frame(maxWidth: 150, alignment: .init(horizontal: .leading, vertical: .center))
                    } else {
                        Image(systemName: "person.crop.circle").resizable().scaledToFit().frame(width: 18, height: 18).padding(8)
                    }
                }
            }
        }
        .sheet(isPresented: $showProfile) {
            Modal(L10n.string("Steam profile"), showModal: $showProfile) {
                VStack() {
                    if isLoading {
                        VStack {
                            ProgressView(L10n.string("Loading profile…"))
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else if let p = profileData {
                        let lastLogOff = p.lastLogOff == nil
                            ? L10n.string("No activity recorded")
                            : Date(timeIntervalSince1970: Double(p.lastLogOff!)).formatted()
                        let timeCreated = Date(timeIntervalSince1970: Double(p.timeCreated)).formatted()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack {
                                    KFImage(URL(string: p.avatarFull))
                                        .placeholder {
                                            ProgressView()
                                        }
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity)
                                }
                                .frame(width: 82, height: 82)
                                .cornerRadius(20)
                                .padding(.trailing, 10)
                                VStack (alignment: .leading){
                                    HStack (alignment: .bottom){
                                        Text(p.personaName).font(.largeTitle)
                                        if (p.locCountryCode != nil){
                                            Flag(countryCode: p.locCountryCode!).font(.largeTitle)
                                        }
                                    }
                                    HStack {
                                        Tag(
                                            p.communityVisibilityState == 3
                                                ? L10n.string("Public")
                                                : L10n.string("Private")
                                        )
                                        Tag(mapPersonaState(p.personaState))
                                    }
                                }
                            }.padding(.bottom)
                            if (p.profileState == 1){
                                Text(L10n.string("Community profile configured"))
                                Text(L10n.string("A \"Steam Community profile configured\" means you have completed the initial setup of your profile, enabling you to use social features like adding friends, posting in hubs, and trading. It requires setting up an avatar, username, and often, spending at least $5.00 USD to unlock features from \"limited account\" status.")).font(.footnote)
                            } else {
                                Text(L10n.string("Community profile needs to be configured"))
                                Text(L10n.string("This means you haven't completed the initial setup of your profile, at the moment you can't use social features like adding friends, posting in hubs, and trading. To configure it, set up an avatar, username, and often, spending at least $5.00 USD will unlock your status.")).font(.footnote)
                            }
                            
                            Text(L10n.format("Steam ID: \n%@", p.steamID))
                            Text(L10n.format("Profile URL: \n%@", p.profileURL))
                            //                    Text("avatarHash: \(p.avatarHash)")
                            //                    Text("primaryClanID: \(p.primaryClanID)")
                            Text(L10n.format("Account created on: \n%@", timeCreated))
                            Text(L10n.format("Last Time you logged off: \n%@", lastLogOff))
                            //                    Text("personaStateFlags: \(p.personaStateFlags)")
                            //                    Text("locStateCode: \(p.locStateCode ?? "-")")
                            Spacer()
                            VStack(alignment: .leading) {
                                ProminentButton(L10n.string("Reload profile data"), systemImage: "arrow.clockwise") {
                                    isLoading = true
                                    api.deleteProfileDataCache()
                                    Task(priority: .background){
                                        await load()
                                    }
                                }
                            }.padding(.top)
                        }
                        .padding(.vertical)
                        .cornerRadius(20)
                    } else {
                        Text(L10n.string("No profile data"))
                    }
                }.frame(width: 500, height: 450, alignment: .center)
            }
        }
        .task(id: displayedIdentity?.cacheKey) {
            isLoading = true
            profileData = nil
            await load()
        }
    }
    
    @MainActor
    private func load() async {
        defer {
            isLoading = false
        }
        do {
            if let identity = displayedIdentity {
                profileData = try await api.fetchProfileDetails(
                    userID: identity.steamID,
                    identityCacheKey: identity.cacheKey
                )
            } else {
                console.error("Couldn't find the userID")
            }
        } catch {
            console.error(String(reflecting: error))
        }
    }

    private func localAvatar(for identity: SteamIdentity) -> NSImage? {
        guard let avatarURL = identity.avatarURL else { return nil }
        return NSImage(contentsOf: avatarURL)
    }
}



#Preview {
    ProfileWidget()
}
