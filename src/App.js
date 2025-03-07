import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Box } from '@mui/material'; // simple div element
import { Navbar, ChannelDetail, Feed, SearchFeed, VideoDetail, WatchHistory, SearchHistory, Playlists, PlaylistDetail } from './components';
import { Login, Signup, Profile } from './components/auth';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import { SearchProvider } from './contexts/SearchContext';
import { PlaylistProvider } from './contexts/PlaylistContext';

// Protected route component
const PrivateRoute = ({ children }) => {
  const { currentUser } = useAuth();
  
  if (!currentUser) {
    return <Navigate to="/login" />;
  }
  
  return children;
};

// Public route that redirects if user is already logged in
const PublicOnlyRoute = ({ children }) => {
  const { currentUser } = useAuth();
  
  if (currentUser) {
    return <Navigate to="/" />;
  }
  
  return children;
};

const AppContent = () => (
  <BrowserRouter>
    <Box sx={{ background: 'linear-gradient(to left, rgba(0, 0, 0, 1), rgba(18, 1, 1, 0.8))'}}>
      <Navbar />
      <Routes>
        {/* Public routes */}
        <Route exact path="/" element={<Feed />} />
        <Route path="/video/:id" element={<VideoDetail />} />
        <Route path="/channel/:id" element={<ChannelDetail />} />
        <Route path="/search/:searchTerm" element={<SearchFeed />} />
        <Route path="/search-history" element={<SearchHistory />} />
        <Route path="/playlists" element={<Playlists />} />
        <Route path="/playlist/:playlistId" element={<PlaylistDetail />} />
        
        {/* Auth routes */}
        <Route path="/login" element={
          <PublicOnlyRoute>
            <Login />
          </PublicOnlyRoute>
        } />
        <Route path="/signup" element={
          <PublicOnlyRoute>
            <Signup />
          </PublicOnlyRoute>
        } />
        
        {/* Protected routes */}
        <Route path="/profile" element={
          <PrivateRoute>
            <Profile />
          </PrivateRoute>
        } />
        <Route path="/history" element={<WatchHistory />} />
      </Routes>
    </Box>
  </BrowserRouter>
);

const App = () => (
  <AuthProvider>
    <SearchProvider>
      <PlaylistProvider>
        <AppContent />
      </PlaylistProvider>
    </SearchProvider>
  </AuthProvider>
);

export default App;

