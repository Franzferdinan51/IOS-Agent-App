//
//  OnboardingView.swift
//  DualAgent
//
//  Created by Hermes Agent on 2026-07-06.
//

import SwiftUI

/// The onboarding view that welcomes new users and guides them through initial setup.
struct OnboardingView: View {
    // MARK: - State
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.colorScheme) private var colorScheme
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // TabView for onboarding screens
            TabView(selection: $viewModel.currentPage) {
                // Welcome Screen
                WelcomeView()
                    .tag(0)
                
                // Features Overview
                FeaturesView()
                    .tag(1)
                
                // Sign In/Sign Up
                SignInUpView(viewModel: viewModel)
                    .tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            
            // Navigation buttons
            HStack {
                // Back button
                if viewModel.currentPage > 0 {
                    Button(action: {
                        withAnimation {
                            viewModel.goToPreviousPage()
                        }
                    }) {
                        Text("Back")
                            .fontWeight(.medium)
                            .frame(minWidth: 80)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                // Next/Done button
                Button(action: {
                    if viewModel.currentPage < viewModel.totalPages - 1 {
                        withAnimation {
                            viewModel.goToNextPage()
                        }
                    } else {
                        // Final page - complete onboarding
                        viewModel.completeOnboarding()
                    }
                }) {
                    Text(viewModel.currentPage < viewModel.totalPages - 1 ? "Next" : "Get Started")
                        .fontWeight(.semibold)
                        .frame(minWidth: 80)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .alert(isPresented: $viewModel.showError) {
            Alert(
                title: Text("Error"),
                message: Text(viewModel.errorMessage ?? "An unknown error occurred"),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(
            Group {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.2))
                }
            }
        )
    }
}

// MARK: - Welcome View
private struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Logo / Icon
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Welcome to DualAgent")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Your AI-powered dual-agent assistant for enhanced productivity and learning")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}

// MARK: - Features View
private struct FeaturesView: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            VStack(spacing: 20) {
                FeatureIconView(
                    icon: "brain.head.profile",
                    title: "Dual AI Agents",
                    description: "Work with both Hermes and OpenClaw agents simultaneously for enhanced reasoning and creativity."
                )
                
                FeatureIconView(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Code Assistance",
                    description: "Get intelligent code suggestions, debugging help, and architecture suggestions."
                )
                
                FeatureIconView(
                    icon: "chart.bar.doc.horizontal",
                    title: "Insights & Analytics",
                    description: "Track your productivity, token usage, and get personalized recommendations."
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .padding(.top, 60)
    }
}

// MARK: - Feature Icon View
private struct FeatureIconView: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.accentColor)
                .frame(width: 80, height: 80)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(16)
            
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
    }
}

// MARK: - Sign In / Sign Up View
private struct SignInUpView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignUp = true
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text(isSignUp ? "Create Account" : "Sign In")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(isSignUp ? 
                "Join DualAgent to start your AI-powered journey" : 
                "Welcome back! Enter your credentials to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(spacing: 16) {
                // Email field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ZStack(alignment: .trailing) {
                        TextField("Enter your email", text: $email)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                        
                        if !email.isEmpty {
                            Button(action: {
                                email = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.trailing, 8)
                        }
                    }
                }
                
                // Password field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ZStack(alignment: .trailing) {
                        Group {
                            if showPassword {
                                TextField("Enter your password", text: $password)
                            } else {
                                SecureField("Enter your password", text: $password)
                            }
                        }
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: {
                            showPassword.toggle()
                        }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .padding(.trailing, 8)
                    }
                    
                    if isSignUp {
                        // Confirm password field
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Confirm Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ZStack(alignment: .trailing) {
                                Group {
                                    if showConfirmPassword {
                                        TextField("Confirm your password", text: $confirmPassword)
                                    } else {
                                        SecureField("Confirm your password", text: $confirmPassword)
                                    }
                                }
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Button(action: {
                                    showConfirmPassword.toggle()
                                }) {
                                    Image(systemName: showConfirmPassword ? "eye.slash" : "eye")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.trailing, 8)
                            }
                            
                            if !confirmPassword.isEmpty && confirmPassword != password {
                                Text("Passwords do not match")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            
            // Action button
            Button(action: {
                if isSignUp {
                    viewModel.signUp(email: email, password: password)
                } else {
                    viewModel.signIn(email: email, password: password)
                }
            }) {
                Text(isSignUp ? "Create Account" : "Sign In")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(!isFormValid || viewModel.isLoading)
            .opacity(isFormValid ? 1.0 : 0.6)
            
            // Toggle between sign in and sign up
            Button(action: {
                isSignUp.toggle()
                // Clear fields when switching
                email = ""
                password = ""
                confirmPassword = ""
            }) {
                Text(isSignUp ? "Already have an account? Sign In" : "Don't have an account? Sign Up")
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .padding(.top, 40)
        .padding(.horizontal, 24)
    }
    
    private var isFormValid: Bool {
        // Basic email validation
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        let isValidEmail = emailPredicate.evaluate(with: email)
        
        let isPasswordValid = password.count >= 6
        
        if isSignUp {
            let isConfirmValid = !confirmPassword.isEmpty && confirmPassword == password
            return !email.isEmpty && isValidEmail && isPasswordValid && isConfirmValid
        } else {
            return !email.isEmpty && isValidEmail && isPasswordValid
        }
    }
}

// MARK: - Preview
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .preferredColorScheme(.light)
        
        OnboardingView()
            .preferredColorScheme(.dark)
    }
}